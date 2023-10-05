#! /usr/bin/env bash

source .modules/logging.sh 2> /dev/null || exit 1
source .modules/common.sh 2> /dev/null  || exit 1

check_requirements direnv               || exit 1

# Docs at https://direnv.net/
