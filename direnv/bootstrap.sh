#! /usr/bin/env bash

source internal/logging.sh 2> /dev/null || exit 1
source internal/common.sh 2> /dev/null  || exit 1

check_requirements direnv               || exit 1

# Docs at https://direnv.net/
