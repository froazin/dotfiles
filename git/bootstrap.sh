echo "Bootstrapping configuration for git..."

function print_help() {
    echo "Usage: git/bootstrap.sh [true|false]"
    echo "If true, will not prompt for username and email."
    echo "If false, will prompt for username and email."
}

if [ ! -x "$(command -v rsync)" ]; then
    echo "ERROR: Bootstrapping git configuration requires rsync. Please install rsync and try again."
    exit 1
fi

username=$(git config --global user.name)
email=$(git config --global user.email)

# rsync files in current directory
rsync --exclude install.sh \
    --exclude bootstrap.sh \
    -avz --no-perms ./git/ $HOME

[[ $username == "" ]] || git config --global user.name "$username"
[[ $username == "" ]] || git config --global user.email "$email"
