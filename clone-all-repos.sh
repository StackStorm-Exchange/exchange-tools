#!/usr/bin/env bash

# Script which clones all the pack repos

DIRECTORY=$1
GITHUB_ORG=${2:-StackStorm-Exchange}
PREFIX=${3:-stackstorm}

if [ -z "${DIRECTORY}" ]; then
    echo "Usage: $0 <path to directory where to clone the repos>"
    exit 2
fi

source $(dirname $0)/functions.sh

_need_gh

pushd ${DIRECTORY}
	for repo_url in $(_gh_list_git_ssh_urls ${GITHUB_ORG} ${PREFIX}); do
		gh repo clone "${repo_url}"
	done
popd
