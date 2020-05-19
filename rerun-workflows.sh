#!/bin/bash
#
# A helper script to bootstrap a new StackStorm Exchange pack.
# Creates tokens and keys, commits circle.yml for CI, adds the
# project to CircleCI.
#
# The script will create a repo with circle.yml, and the initial
# contents of the pack should be then submitted as a PR to perform
# linting and test run. After the PR is merged, the index will
# be updated, and version tags will be inferred from commit history.
#
# Requires: httpie, jq
#
# The following env variables must be specified:
# * GITHUB_USERNAME: a GitHub user to run the script under (Exchange bot).
# * GITHUB_PASSWORD: password for the user (not a token).
# * CIRCLECI_TOKEN: a CircleCI token for the Exchange organization.
#
# Optional env variables:
# * EXCHANGE_ORG: the GitHub organization to use, default: StackStorm-Exchange

set -e

if [[ -z "$GITHUB_USERNAME" ]]; then
	echo "Please enter the GitHub username to authenticate as:"
	read GITHUB_USERNAME
fi
if [[ -z "$GITHUB_PASSWORD" ]]; then
	echo "Please enter the GitHub password for the $GITHUB_USERNAME user to "
	echo "authenticate with:"
	# https://stackoverflow.com/a/3980713
	stty -echo
	read -s GITHUB_PASSWORD
	stty echo
fi
if [[ -z "$CIRCLECI_TOKEN" ]]; then
	echo "Please enter the CircleCI user token to use:"
	# https://stackoverflow.com/a/3980713
	stty -echo
	read -s CIRCLECI_TOKEN
	stty echo
fi


if [[ -z "$GITHUB_USERNAME" ]]; then
	echo >&2 "Error: You must specify the GITHUB_USERNAME environment variable"
	echo >&2 "       or enter it when prompted."
	echo >&2 "       This should probably be the stackstorm-neptr GitHub user."
	echo >&2 "Exiting."
	exit 1
fi
if [[ -z "$GITHUB_PASSWORD" ]]; then
	echo >&2 "Error: You must specify the GITHUB_PASSWORD environment variable"
	echo >&2 "       or enter it when prompted."
	echo >&2 "       If you are using the stackstorm-neptr user, the password"
	echo >&2 "       should be shared in LastPass."
	echo >&2 "Exiting."
	exit 1
fi
if [[ -z "$CIRCLECI_TOKEN" ]]; then
	echo >&2 "Error: You must specify the CIRCLECI_TOKEN environment variable"
	echo >&2 "       or enter it when prompted."
	echo >&2 "       To generate a new token, browse to "
	echo >&2 "       https://circleci.com/dashboard"
	echo >&2 "       then go to your user settings, and your"
	echo >&2 "       'Personal API Tokens'."
	echo >&2 "Exiting."
	exit 1
fi


GITHUB_ORG=${EXCHANGE_ORG:-StackStorm-Exchange}
EXCHANGE_PREFIX="${EXCHANGE_PREFIX:-stackstorm-}"
# BRANCH=${BRANCH:-master}


LINK_HEADER=$(https -a "$GITHUB_USERNAME:$GITHUB_PASSWORD" --headers "https://api.github.com/orgs/$GITHUB_ORG/repos" | grep 'Link:')

GH_ORG_ID=$(echo $LINK_HEADER | sed 's|Link: <.*https://api.github.com/organizations/\([[:digit:]]*\)/repos?page=[[:digit:]]*>\; rel="next".*|\1|')
NEXT_PAGE=$(echo $LINK_HEADER | sed 's|Link: <.*https://api.github.com/organizations/[[:digit:]]*/repos?page=\([[:digit:]]*\)>\; rel="next".*|\1|')
LAST_PAGE=$(echo $LINK_HEADER | sed 's|Link: <.*https://api.github.com/organizations/[[:digit:]]*/repos?page=\([[:digit:]]*\)>\; rel="last".*|\1|')

FIRST_PAGE=$NEXT_PAGE
if [[ "$FIRST_PAGE" -gt 1 ]]; then
	FIRST_PAGE=$(expr $FIRST_PAGE - 1)
fi

for page in $(seq $FIRST_PAGE $LAST_PAGE); do
	for REPO_NAME in $(https -a "$GITHUB_USERNAME:$GITHUB_PASSWORD" "https://api.github.com/orgs/$GITHUB_ORG/repos?page=$page" | jq -r '.[].name');do
		if [[ "${REPO_NAME:0:${#EXCHANGE_PREFIX}}" != "stackstorm-" ]]; then
			continue
		fi
		if [[ "${REPO_NAME:0:15}" = "stackstorm-test" ]]; then
			continue
		fi
		echo $REPO_NAME

		# GitHub: create a personal access token
		echo "Github: Creating a GitHub personal access token"
		GITHUB_PERSONAL_ACCESS_TOKEN=$(echo "
			{
				\"scopes\": [
					\"public_repo\"
				],
				\"note\": \"CircleCI: ${REPO_NAME}\"
			}" \
			| https -a "${GITHUB_USERNAME}:${GITHUB_PASSWORD}" POST "https://api.github.com/authorizations" \
			| jq ".token")

		sleep 1

		# CircleCI: specify the credential (the new personal access token)
		echo "CircleCI: Setting credential (user-scoped personal access token)"
		echo "
		{
			\"name\": \"MACHINE_PASSWORD\",
			\"value\": \"$GITHUB_PERSONAL_ACCESS_TOKEN\"
		}" \
		| https POST "https://circleci.com/api/v1.1/project/github/${GITHUB_ORG}/${REPO_NAME}/envvar?circle-token=${CIRCLECI_TOKEN}"

		sleep 2

		# Now that we've reset the GitHub personal access token, rerun the
		# entire project build
		# https://circleci.com/docs/api/#trigger-a-new-build-by-project-preview
		https POST "https://circleci.com/api/v1.1/project/gh/$GITHUB_ORG/$REPO_NAME/build?circle-token=${CIRCLECI_TOKEN}"

		echo "Waiting for four minutes so only one build step runs at once"
		sleep 240
	done
done
