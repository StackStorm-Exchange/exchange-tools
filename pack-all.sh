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

FAIL_FAST=true
SKIPIF=

STDOUT_LOGFILE=/dev/stdout
STDERR_LOGFILE=/dev/stderr
while [[ -n "$1" ]]; do
    if [[ "${1:0:2}" = "--" ]]; then
        # TODO: Add skipifbranch to skip if the git branch matches
        if [[ "${1:2:6}" = "skipif" ]]; then
            SKIPIF="${1:9}"
        elif [[ "${1:2}" == "continue-on-error" ]]; then
            FAIL_FAST=
        elif [[ "${1:2}" == verbose* ]]; then
            if [[ "${1:2}" == verbose=* ]]; then
                VERBOSE="${1:10}"
            else
                VERBOSE=1
            fi
        elif [[ "${1:2}" = "help" ]]; then
            echo >&2 "Usage: pack-all.sh --skipif='[[ <condition> ]]' <command> <command-arguments>"
            echo >&2 ""
            echo >&2 "This script is used for performing Bash operations across all packs."
            echo >&2 ""
            echo >&2 "Examples:"
            echo >&2 ""
            echo >&2 "pack-all.sh --skipif='[[ \\$(git branch) ]]' yq"
            echo >&2 ""
            exit 1
        elif [[ "${1:2}" = "quiet" ]]; then
            VERBOSE=0
            STDOUT_LOGFILE=/dev/null
        elif [[ "${1:2}" = "silent" ]]; then
            VERBOSE=0
            STDOUT_LOGFILE=/dev/null
            STDERR_LOGFILE=/dev/null
        else
            echo >&2 "Unrecognized flag: $1. Exiting"
            exit 1
        fi
        shift
    else
        break
    fi
done

COMMAND=$1; shift

if [[ -z "$COMMAND" ]]; then
    COMMAND='basename $(pwd)'
    # echo >&2 "You must specify a git command as the first argument. Exiting."
    # exit 1
fi

for pack in $(find . -type f -name 'pack.yaml' -depth 2 -exec sh -c 'basename $(dirname {})' \; | grep '^stackstorm-' | sort); do
    [[ $VERBOSE -gt 4 ]] && echo "In $pack"
    # Not 100% sure this is bug-free
    if [[ -n "$SKIPIF" ]]; then
        (cd $(pwd)/$pack && eval 1>/dev/null $SKIPIF) && continue
    fi
    [[ $VERBOSE -le 4 && "$COMMAND" != 'basename $(pwd)' ]] && echo "In $pack"
    (
        cd "$(pwd)/$pack"
        eval >$STDOUT_LOGFILE 2>$STDERR_LOGFILE $COMMAND $*
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
