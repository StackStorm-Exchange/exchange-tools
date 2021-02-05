#### dependency declarations

# `which -s` would be nice, but -s is not portable.
# see: https://unix.stackexchange.com/a/85250/77115

_need_http() {
    if ! command -v http &>/dev/null; then
        echo >&2 "This script requires the 'http' command to be installed and accessible in the \$PATH."
        echo >&2 "Please install the httpie package and rerun this command."
        echo >&2 "Exiting."
        exit 2
    fi
}

_need_jq() {
    if ! command -v jq &>/dev/null; then
        echo >&2 "This script requires the 'jq' command to be installed and accessible in the \$PATH."
        echo >&2 "Please install the jq package and rerun this command."
        echo >&2 "Exiting."
        exit 2
    fi
}

_need_gh() {
    if ! command -v gh &>/dev/null; then
        echo >&2 "This script requires the 'gh' command to be installed and accessible in the \$PATH."
        echo >&2 "Please install gh, the github cli package, and rerun this command."
        echo >&2 "For gh install instructions see: https://github.com/cli/cli#installation"
        echo >&2 "Exiting."
        exit 2
    fi
	_need_jq  # all gh actions use jq to process the results
}

#### gh helpers

_gh_repos_query() {
	# List git repo attribute in ORG that begin with prefix
	# _gh_repos_query StackStorm-Exchange stackstorm- sshUrl

    GITHUB_ORG=${1}
	PREFIX=${2}
	ATTR=${3}
	if [[ ${ATTR} != "name" ]]; then
		ATTRS="name ${ATTR}"
	else
		ATTRS="${ATTR}"
	fi

    # based on https://github.com/cli/cli/issues/642#issuecomment-693598673
    gh api --paginate graphql -f owner="${GITHUB_ORG}" -f query='
      query($owner: String!, $per_page: Int = 100, $endCursor: String) {
        repositoryOwner(login: $owner) {
          repositories(first: $per_page, after: $endCursor, ownerAffiliations: OWNER) {
            nodes { '"${ATTRS}"' }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    ' | jq -r '.data.repositoryOwner.repositories.nodes[] | select(.name | startswith("'"${PREFIX}"'")).'"${ATTR}" \
    | sort
}


_gh_list_git_ssh_urls() {
	# List git ssh urls in ORG that begin with prefix
    GITHUB_ORG=${1}
	PREFIX=${2}
	_gh_repos_query "${GITHUB_ORG}" "${PREFIX}" sshUrl
}

_gh_list_repo_names() {
	# List git ssh urls in ORG that begin with prefix
    GITHUB_ORG=${1}
	PREFIX=${2}
	_gh_repos_query "${GITHUB_ORG}" "${PREFIX}" name
}

_gh_default_branch() {
    # get the default branch for the current repo (might not be master)

    gh api graphql -F owner=':owner' -F name=':repo' -f query='
      query($name: String!, $owner: String!) {
        repository(owner: $owner, name: $name) {
          defaultBranchRef { name }
        }
      }
    ' | jq -r '.data.repository.defaultBranchRef.name'
}

_gh_is_merged_in_default() {
	# you can specify which remote like:
	# _gh_is_merged_in_default upstream
	REMOTE=${1}${1:+/}
	git merge-base --is-ancestor HEAD ${REMOTE}$(_gh_default_branch)
}

_gh_pr_created() {
    # return true if there is a current pr for this branch
	BRANCH=${1:-$(git branch --show-current)}
	echo $BRANCH

    gh api graphql -F owner=':owner' -F name=':repo' -F headRefName="${BRANCH}" -f query='
      query($name: String!, $owner: String!, $headRefName: String!) {
        repository(owner: $owner, name: $name) {
          pullRequests(headRefName: $headRefName, first: 1) {
			nodes { title }
		  }
        }
      }
    ' | jq -e -r '.data.repository.pullRequests.nodes[].title'
}

_gh_url() {
    # get the https git clone url for the current repo

    gh api graphql -F owner=':owner' -F name=':repo' -f query='
      query($name: String!, $owner: String!) {
        repository(owner: $owner, name: $name) { url }
      }
    ' | jq -r '.data.repository.url + ".git"'
}

_gh_url_with_token() {
	# get the https git clone url with a PAT included
	USER=${1}
	TOKEN=${2}

	_gh_url | sed -e "s|//|//${USER}:${TOKEN}@|"
}

