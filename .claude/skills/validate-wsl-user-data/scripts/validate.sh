#!/usr/bin/env sh
#
# Render src/wsl/ubuntu.user-data against mock instance-data and validate the
# result. The user-data is a Jinja template, so `cloud-init schema` on the raw
# file is meaningless; every case has to be rendered first.
#
# Usage: validate.sh [path/to/ubuntu.user-data]

set -u

user_data="${1:-src/wsl/ubuntu.user-data}"
failed="false"

fail()
{
    printf 'FAIL: %s\n' "$*"
    failed="true"
}

for cmd in cloud-init python3 git shellcheck; do
    command -v "$cmd" > /dev/null 2>&1 || {
        printf 'missing required command: %s\n' "$cmd" >&2
        exit 2
    }
done

[ -f "$user_data" ] || {
    printf 'user-data not found: %s\n' "$user_data" >&2
    exit 2
}

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

# Each case is a meta-data mapping plus the expectations checked below:
#   user      - whether user-specific config should render
#   gh_dir    - expected ~/workspaces/github.com/<owner> directory, or ""
#   git_name  - exact user.name git must read back from the rendered .gitconfig
python3 -I - "$work" << 'EOF'
import json
import sys

work = sys.argv[1]

v1 = {
    "cloud_name": "wsl", "platform": "wsl", "cloud_id": "wsl",
    "distro": "ubuntu", "distro_release": "resolute", "distro_version": "26.04",
    "instance_id": "ubuntu-wsl", "local_hostname": "host", "region": None,
    "availability_zone": None, "kernel_release": "6", "machine": "x86_64",
    "python_version": "3", "variant": "ubuntu", "subplatform": "unknown",
    "system_platform": "x", "public_ssh_keys": [],
}

hostile = "O'Hara \"Q\" \\ # ; {{ x }}"

cases = {
    "full": ({"username": "jdoe", "git_name": "Jane Doe",
              "git_email": "1+jdoe@users.noreply.github.com",
              "git_signingkey": "ssh-ed25519 AAAA jane",
              "git_ssh_program": "/mnt/c/Users/<you>/op-ssh-sign-wsl.exe"},
             {"user": True, "gh_dir": "jdoe", "git_name": "Jane Doe"}),
    "empty-values": ({"username": None, "git_name": None},
                     {"user": False, "gh_dir": "", "git_name": ""}),
    "no-meta-data": ({}, {"user": False, "gh_dir": "", "git_name": ""}),
    "hostile-name": ({"username": "jdoe", "git_name": hostile},
                     {"user": True, "gh_dir": "", "git_name": hostile}),
    "legacy-noreply": ({"username": "jdoe", "git_email": "jdoe@users.noreply.github.com"},
                       {"user": True, "gh_dir": "jdoe", "git_name": ""}),
    "plain-email": ({"username": "jdoe", "git_email": "jane@example.com"},
                    {"user": True, "gh_dir": "", "git_name": ""}),
    "path-traversal": ({"username": "jdoe", "git_email": "1+../../etc@users.noreply.github.com"},
                       {"user": True, "gh_dir": "", "git_name": ""}),
}

with open(f"{work}/cases", "w") as index:
    for name, (meta, expect) in cases.items():
        meta = {"instance-id": "ubuntu-wsl", **meta}
        with open(f"{work}/{name}.json", "w") as f:
            json.dump({"v1": v1, "ds": {"meta_data": meta}}, f)
        with open(f"{work}/{name}.expect.json", "w") as f:
            json.dump(expect, f)
        index.write(name + "\n")
EOF

while read -r case; do
    rendered="$work/$case.yaml"

    if ! cloud-init devel render -i "$work/$case.json" "$user_data" > "$rendered" 2> "$work/$case.err"; then
        fail "$case: render failed: $(tail -1 "$work/$case.err")"
        continue
    fi

    if grep -q 'CI_MISSING_JINJA_VAR' "$rendered"; then
        fail "$case: rendered output references an undefined Jinja variable"
    fi

    if ! cloud-init schema -c "$rendered" > "$work/$case.schema" 2>&1; then
        fail "$case: schema: $(grep -v 'obj.pkl\|datasource' "$work/$case.schema" | head -3)"
    fi

    python3 -I - "$rendered" "$work/$case.expect.json" "$work/$case" << 'EOF' || failed="true"
import json
import subprocess
import sys

rendered, expect_path, prefix = sys.argv[1:]
case = prefix.rsplit("/", 1)[-1]
expect = json.load(open(expect_path))
text = open(rendered).read()
doc = __import__("yaml").safe_load(text)
problems = []

if not text.startswith("#cloud-config"):
    problems.append("rendered output does not start with #cloud-config")

files = {f["path"]: f for f in doc.get("write_files", [])}
gitconfig = next((f for p, f in files.items() if p.endswith("/.gitconfig")), None)
has_user = "users" in doc

if has_user != expect["user"]:
    problems.append(f"users rendered={has_user}, expected {expect['user']}")
if (gitconfig is not None) != expect["user"]:
    problems.append(f".gitconfig rendered={gitconfig is not None}, expected {expect['user']}")

runcmd = json.dumps(doc.get("runcmd", []))
gh_dirs = [part for part in runcmd.split('"') if "/workspaces/github.com/" in part and "mkdir" not in part]
want = expect["gh_dir"]
mkdirs = [d for d in gh_dirs if d.startswith("/home/")]
if want and not any(d.endswith(f"/workspaces/github.com/{want}") for d in mkdirs):
    problems.append(f"expected workspace dir github.com/{want}, got {mkdirs}")
if not want and mkdirs:
    problems.append(f"unexpected workspace dirs {mkdirs}")

# Root: login shell set first, then the dotfiles installed after the user's.
cmds = [c if isinstance(c, list) else [c] for c in doc.get("runcmd", [])]
def find(pred):
    return next((i for i, c in enumerate(cmds) if pred(c)), None)
root_shell = find(lambda c: "usermod -s /usr/bin/zsh root" in " ".join(map(str, c)))
root_install = find(lambda c: c[:3] == ["runuser", "-l", "root"])
user_install = find(lambda c: c[:2] == ["runuser", "-l"] and c[2] != "root" and "src/install.sh" in str(c[-1]))
if root_shell is None:
    problems.append("runcmd does not set root's login shell")
if root_install is None:
    problems.append("runcmd does not install the dotfiles for root")
else:
    script = str(cmds[root_install][-1])
    if root_shell is not None and root_install < root_shell:
        problems.append("root's dotfiles install runs before its login shell is set")
    if "~" in script:
        problems.append("root's install path uses ~, which runuser -l expands to /root")
    if expect["user"] and (user_install is None or root_install < user_install):
        problems.append("root's install does not follow the user's clone")
    if not expect["user"] and "mktemp" not in script:
        problems.append("root's install without a user does not use a throwaway clone")

if gitconfig is not None:
    with open(prefix + ".gitconfig", "w") as f:
        f.write(gitconfig["content"])
    got = subprocess.run(["git", "config", "-f", prefix + ".gitconfig", "--get", "user.name"],
                         capture_output=True, text=True)
    if got.returncode not in (0, 1):
        problems.append(f"git cannot parse .gitconfig: {got.stderr.strip()}")
    elif got.stdout.rstrip("\n") != expect["git_name"]:
        problems.append(f"user.name read back as {got.stdout.rstrip()!r}, expected {expect['git_name']!r}")

start = files.get("/usr/local/bin/start")
if start is not None:
    with open(prefix + ".start", "w") as f:
        f.write(start["content"])

for p in problems:
    print(f"FAIL: {case}: {p}")
print(f"{'ok  ' if not problems else 'FAIL'} {case}")
sys.exit(1 if problems else 0)
EOF
done < "$work/cases"

# The embedded start script is the same in every render.
if [ -f "$work/full.start" ]; then
    shellcheck -s sh "$work/full.start" || fail "start: shellcheck"
fi

# A concrete Windows profile path means a username has leaked into the repo.
if grep -nE '/mnt/c/Users/[^<*/ ]+/' "$user_data" | grep -v '<you>'; then
    fail "user-data contains a concrete /mnt/c/Users/<name>/ path"
fi

if [ "$failed" = "true" ]; then
    exit 1
fi

printf 'All cases passed.\n'
