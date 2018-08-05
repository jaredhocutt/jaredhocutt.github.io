#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

function print_status() {
    echo
    echo -e "\033[0;32m${1}\033[0m"
    echo
}

print_status "Building site..."

hugo

cd "${DIR}/public"

print_status "Generating GitHub Pages artifacts..."

touch .nojekyll
echo "jaredhocutt.com" > CNAME

print_status "COMPLETE"
