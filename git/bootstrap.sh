echo "Bootstrapping configuration for git..."

if [ ! -x "$(command -v rsync)" ]; then
    echo "ERROR: Bootstrapping git configuration requires rsync. Please install rsync and try again."
    exit 1
fi

# rsync files in current directory
rsync --exclude install.sh \
    --exclude bootstrap.sh \
    -avz --no-perms ./git/ ~

# prompt user for git username and email
read -p "Enter your git username: " username
read -p "Enter your git email address: " email

# set git config values
git config --global user.name "$username"
git config --global user.email "$email"
