for file in $(ls -f .private/*.sh); do
    source $file
done

if [ ! -x "$(command -v rsync)" ]; then
    write_log "ERROR" "Bootstrapping git configurations requires rsync. Please install rsync and try again."
    exit 1
fi

username=$(git config --global user.name)
email=$(git config --global user.email)

# rsync files in current directory
write_log $INFO "Running git configuration..."
rsync --exclude install.sh \
    --exclude bootstrap.sh \
    -avz --no-perms ./git/ $HOME > /dev/null 2>&1 || exit 1

if ! [ -z "$username" ]; then
    write_log $DEBUG "Persisting existing git configuration for global user.name: $username"
    git config --global user.name "$username" || exit 1
fi

if ! [ -z "$email" ]; then
    write_log $DEBUG "Persisting existing git configuration for global user.email: $email"
    git config --global user.email "$email" || exit 1
fi

exit 0
