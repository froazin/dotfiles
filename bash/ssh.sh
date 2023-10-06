# --- SSH Agent --- #
eval $(ssh-agent -s) 2>&1 > /dev/null

for key in $(ls ~/.ssh/id_*); do
    key=$(basename $key)
    if [[ $key =~ \. ]]; then
        continue
    fi
    ssh-add ~/.ssh/$key 2> /dev/null
done
