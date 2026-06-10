#!/usr/bin/env sh

github_api_request() {
    request_method="$1"
    request_uri="$2"
    request_body="${3:-}"

    if [ ! "$request_method" = "GET" ] && [ ! "$request_method" = "POST" ] && [ ! "$request_method" = "PUT" ] && [ ! "$request_method" = "DELETE" ]; then
        log error "$request_method is not a valid HTTP method."
        return 1
    fi

    if [ -z "$request_uri" ]; then
        log error "Request URI is required."
        return 1
    fi
    request_uri="$(echo "$request_uri" | sed -r 's/^\///')"

    set -- \
        "-X" "$request_method" \
        "-H" "Accept: application/vnd.github.v3+json" \
        "-H" "User-Agent: @froazin/dotfiles" \
        "-H" "Accept-Encoding: utf-8"

    # If GITHUB_TOKEN is set, use it to authenticate the request to avoid a lower rate limit.
    if [ -n "${GITHUB_TOKEN:-""}" ]; then
        log info "Using GITHUB_TOKEN for authentication."
        set -- "$@" "-H" "Authorization: token ${GITHUB_TOKEN}"
    fi

    if [ -n "$request_body" ]; then
        if ! printf '%s' "$request_body" | jq --exit-status . >/dev/null 2>&1; then
            log error "Failed to parse request body as JSON."
            return 1
        fi

        set -- "$@" \
            "-H" "Content-Type: application/json" \
            "-d" "$(printf '%s' "$request_body" | jq -c .)" || {
            log error "Failed to parse request body as JSON."
            return 1
        }
    fi

    curl -fL "$@" "https://api.github.com/$request_uri" 2>/dev/null || {
        log error "Failed to make request to GitHub API."
        return 1
    }

    return 0
}

get_github_release_with_tag() {
    # Fetch the JSON formatted payload for the github release at the given tag.
    owner="$1"
    repo="$2"

    if [ "$3" = "latest" ]; then
        tag="latest"
    else
        tag="tags/$3"
    fi

    if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$tag" ]; then
        return 1
    fi

    github_api_request GET "repos/$owner/$repo/releases/$tag" 2>/dev/null || {
        return 1
    }

    return 0
}

get_github_latest_release() {
    # Fetch the JSON formatted payload for the latest github release.
    owner="$1"
    repo="$2"

    if [ -z "$owner" ] || [ -z "$repo" ]; then
        return 1
    fi

    get_github_release_with_tag "$owner" "$repo" "latest" || {
        return 1
    }

    return 0
}

get_github_refs() {
    # Fetch the JSON formatted payload for the github repo refs. Provide an
    # optional ref or partial ref to search for a specific ref. If multiple
    # matching refs are found, all matching refs will be returned.
    owner="$1"
    repo="$2"
    ref="$3"

    if [ -z "$owner" ] || [ -z "$repo" ]; then
        return 1
    fi

    if [ -z "$ref" ]; then
        uri="repos/$owner/$repo/git/refs"
    else
        uri="repos/$owner/$repo/git/refs/$(echo "$ref" | sed -r 's/^\///')"
    fi

    github_api_request GET "$uri" 2>/dev/null || {
        return 1
    }

    return 0
}

get_github_ref() {
    # Fetch the JSON formatted payload for the github repo ref.
    owner="$1"
    repo="$2"
    ref="$3"

    if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$ref" ]; then
        return 1
    fi

    uri="repos/$owner/$repo/git/ref/$(echo "$ref" | sed -r 's/^\///')"

    github_api_request GET "$uri" 2>/dev/null || {
        return 1
    }

    return 0
}
