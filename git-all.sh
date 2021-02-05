#!/bin/bash

SIGINT_STOP=
_stop() {
    SIGINT_STOP=stop
}

trap _stop SIGINT

_exit() {
    [[ -n "$2" ]] && echo "$2" 2>$STDERR_LOGFILE
    exit $1
}

source $(dirname $0)/functions.sh

_check_dependencies() {
    _need_gh
}


_clone_organization() {
    GITHUB_ORG=$1
	for repo in $(_gh_list_repo_names ${GITHUB_ORG} ''); do
		# Clone the repository if it doesn't exist
		if [[ ! -d "$repo" ]]; then
			gh repo clone ${GITHUB_ORG}/${repo}
		else (
				# If it does exist, fetch all branches
				echo "In $repo" >$STDOUT_LOGFILE 2>$STDERR_LOGFILE
				cd $repo
				git fetch --all >$STDOUT_LOGFILE 2>$STDERR_LOGFILE
			)
		fi
		EXIT_CODE=$?
		[[ $EXIT_CODE -eq 0 ]] || {
			[[ "$FAIL_FAST" == "true" ]] && {
				_exit $EXIT_CODE "Exiting on error"

			}
		}
		[[ -n "$SIGINT_STOP" ]] && {
			echo "Caught SIGINT. Exiting." >$STDOUT_LOGFILE
			_exit 0
		}
    done
}


_check_dependencies

FAIL_FAST=true

STDOUT_LOGFILE=/dev/stdout
STDERR_LOGFILE=/dev/stderr
while [[ -n "$1" ]]; do
    if [[ "${1:0:2}" = "--" ]]; then
        if [[ "${1:2}" == "continue-on-error" ]]; then
            FAIL_FAST=
        elif [[ "${1:2}" = "help" ]]; then
            echo >&2 "Usage: git-all.sh <git-subcommand> <arguments/options>"
            echo >&2 ""
            echo >&2 "This script is used for performing git operations across all packs."
            echo >&2 ""
            echo >&2 "Examples:"
            echo >&2 ""
            echo >&2 "git-all.sh clone StackStorm-Exchange"
            echo >&2 "git-all.sh checkout master"
            echo >&2 "git-all.sh pull"
            echo >&2 "git-all.sh checkout -b add-feature"
            echo >&2 "git-all.sh commit -m \"Commit message\""
            echo >&2 "git-all.sh push --set-upstream origin add-feature"
            echo >&2 ""
            exit 1
        elif [[ "${1:2}" = "quiet" ]]; then
            STDOUT_LOGFILE=/dev/null
        elif [[ "${1:2}" = "silent" ]]; then
            STDOUT_LOGFILE=/dev/null
            STDERR_LOGFILE=/dev/null
        else
            echo >&2 "Unrecognized flag: $1. Exiting"
            exit 1
        fi
        shift
    fi
    break
done

SUBCOMMAND=$1; shift

if [[ -z "$SUBCOMMAND" ]]; then
    echo >&2 "You must specify a git command as the first argument. Exiting."
    exit 1
elif [[ "$SUBCOMMAND" = "clone" ]]; then
    GITHUB_ORG=$1; shift
    if [[ -z "$GITHUB_ORG" ]]; then
        echo >&2 "You must specify an organization as the second argument. Exiting."
        exit 1
    fi
    _clone_organization $GITHUB_ORG
else
    # TODO: Take the for loop from pack-all.sh
    for repo in $(find $(pwd) -type d -depth 1 -exec basename {} \; | sort); do
        [[ -d "$(pwd)/$repo/.git" ]] || continue
        (
            echo "In $repo"
            cd "$(pwd)/$repo"
            git "$SUBCOMMAND" $* >$STDOUT_LOGFILE 2>$STDERR_LOGFILE
        ) || {
            EXIT_CODE=$?
            [[ "$FAIL_FAST" == "true" ]] && {
                _exit $EXIT_CODE "Exiting on error"

            }
        }
        [[ -n "$SIGINT_STOP" ]] && {
            echo "Caught SIGINT. Exiting." >$STDOUT_LOGFILE
            _exit 0
        }
    done
fi
