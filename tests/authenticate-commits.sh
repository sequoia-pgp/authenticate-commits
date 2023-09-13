#! /bin/bash

# This script can be run locally or via GitHub actions.  If you want
# to run it locally, just run the script and it will tell you what
# variables you need to set.

# Where to run the test.
OWNER=${OWNER:-sequoia-pgp}
REPO=${REPO:-authenticate-commits-unit-tests}

# To generate a personal access token, go to your profile and then:
#
#   - Top-Right Menu
#   - Settings
#   - Developer Settings
#   - Personal access tokens
#   - Find-grained Tokens
#   - Generate new token
#   - Generate new token (fine-grained, repo-scoped)
#
#   - Token name: authenticate-commits
#   - Description: For running units tests in the
#     sequoia-pgp/authenticate-commits-unit-tests repository.
#   - Resource owner: sequoia-pgp
#   - Only select repositories
#   - sequoia-pgp/authenticate-commits-unit-tests
#   - Permissions: Actions, Commit statuses, Contents, Issues, Pull requests, Workflows
#   - Generate token
#
# Then you can locally run:
#
#   $ OWNER=sequoia-pgp REPO=authenticate-commits-unit-tests GITHUB_ACTOR=nwalfield \
#     GITHUB_TOKEN=github_pat_... tests/fast-forward.sh
#
# To add the token to the repository so that the CI tests work, go to:
#
#   https://github.com/sequoia-pgp/authenticate-commits/settings/secrets/actions
#
# or:
#
#   Settings, Secrets and variables, Actions, New repository secret
#
# And enter:
#
#   - Name: AUTHENTICATE_COMMITS_UNIT_TESTS_TOKEN
#   - Secret: The token
#
# Note: the name is meaningful and is used by the
# tests/authenticate-commits.sh script.
if test "x$GITHUB_TOKEN" = x -a "x$AUTHENTICATE_COMMITS_UNIT_TESTS_TOKEN" = x
then
    echo "Either the GITHUB_TOKEN or the AUTHENTICATE_COMMITS_UNIT_TESTS_TOKEN environment variable needs to be set."
    exit 1
fi

# Prefer AUTHENTICATE_COMMITS_UNIT_TESTS_TOKEN (which is a secret known to the
# authenticate-commits repository), but when that is not set try GITHUB_TOKEN,
# which works with personal access tokens, and when the action is run
# from the same repository.
TOKEN="${AUTHENTICATE_COMMITS_UNIT_TESTS_TOKEN:-$GITHUB_TOKEN}"

if test x$GITHUB_ACTOR = x
then
    echo "GITHUB_ACTOR environment variable (your GitHub user name) is not set, but is required."
    exit 1
fi

# Print the environment (for debugging purposes).
echo "::group::env"
env
echo "::endgroup::"


TEMPFILES=$(mktemp)
echo -n "$TEMPFILES" >> "$TEMPFILES"
function maketemp {
    F=$(mktemp $*)
    echo -n " $F" >> $TEMPFILES
    echo "$F"
}
function maketemp_exit {
    TEMPFILES=$(cat $TEMPFILES)
    if test x"$TEMPFILES" != x
    then
        echo -e "Clean up temporary files by running:\n  $ rm -rf $TEMPFILES"
    fi
}
trap maketemp_exit EXIT

set -ex

# Files from the authenticate-commits repository that we copy over.
FILES=".github/workflows/authenticate-commits.yml"

AUTHENTICATE_COMMITS_REPO=$(git rev-parse --show-toplevel)
for f in $FILES
do
    if ! test -e "$AUTHENTICATE_COMMITS_REPO/$f"
    then
        echo "Missing \"$f\".  Are you really in the authenticate-commits repo?"
        exit 1
    fi
done

if ! test -z "$(git status --untracked-files=no --porcelain)"
then
    echo "You appear to have uncommitted changes.  You have to push your changes to actually test them."
    git status --untracked-files=no
    exit 1
fi

# The workflows need to point to the code that we actually want to
# test.  That is is probably not the released version of the actions,
# and it not necessarily the repository where we'll do the tests
# (i.e., create the pull request).  The current checkout *is* the code
# we want to test.  So we need to make sure the actions installed in
# the unit test repository reference those actions.
#
# GITHUB_REPOSITORY (OWNER/REPO) and GITHUB_HEAD_REF (a commit hash)
# refer to the commit we are testing.  If they are not set, then we
# are running locally.
#
# GITHUB_REPOSITORY is of the form OWNER/REPO.  It is the repository
# that contains the code that we are testing (as opposed to the test
# repository where we'll make a pull request, etc.).
if test "x$GITHUB_REPOSITORY" = x
then
    echo "GITHUB_REPOSITORY unset.  Inferring from origin."
    ORIGIN=$(git remote get-url origin)
    # We expect one of:
    #
    #  - https://username@github.com/sequoia-pgp/authenticate-commits.git
    #  - git@github.com:sequoia-pgp/authenticate-commits.git
    #
    # We split on github.com
    GITHUB_REPOSITORY=$(echo "$ORIGIN" \
                            | awk -F"github[.]com[:/]" '{
                                  sub(/[.]git/, "");
                                  print $2;
                              }')
    if test "x$GITHUB_REPOSITORY" = x
    then
        echo "Unable to extract OWNER/REPO from origin ($ORIGIN)"
        exit 1
    fi
fi
echo "GITHUB_REPOSITORY: $GITHUB_REPOSITORY"

if test "x$GITHUB_HEAD_REF" = x
then
    echo "GITHUB_HEAD_REF unset.  Using HEAD."
    GITHUB_HEAD_REF=$(git rev-parse HEAD)
fi
echo "GITHUB_HEAD_REF: $GITHUB_HEAD_REF"

# Check that the branch has been pushed to origin.
if test -z "$(git branch -r --list 'origin/*' --contains $GITHUB_HEAD_REF)"
then
    # https://docs.github.com/en/actions/learn-github-actions/variables
    #
    #   GITHUB_REF_TYPE: The type of ref that triggered the workflow
    #   run. Valid values are branch or tag.
    #
    # Note: when run from the command line (i.e., not from CI), the
    # user probably did not set GITHUB_REF_TYPE.
    if test "x$GITHUB_REF_TYPE" != xtag
    then
        echo "The commit we want to test ($GITHUB_HEAD_REF) does not appear to have been pushed to origin."
        git branch -r | while read b; do git log --format=oneline -n 1 "$b"; done
        exit 1
    fi
fi

echo "::group::Initializing scratch repository"

D=$(maketemp -d)
echo "Scratch directory: $D"
cd $D

git init --initial-branch main .
git config user.name "Authenticate Commits Unit Test"
git config user.email "neal@sequoia-pgp.org"

git config credential.helper store
{
    echo "url=https://$GITHUB_ACTOR@github.com/$OWNER/$REPO.git"
    echo "username=$GITHUB_ACTOR"
    echo "password=$TOKEN"
} | git credential approve

git remote add origin "https://$GITHUB_ACTOR@github.com/$OWNER/$REPO.git"

# Make sure our BASE is the default branch so that the workflows we
# want to test will run.
REPO_PROPERTIES=$(maketemp)
curl --silent --show-error --output $REPO_PROPERTIES -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/$OWNER/$REPO
DEFAULT_BRANCH=$(jq -r ".default_branch" < $REPO_PROPERTIES)
if test x$DEFAULT_BRANCH = x
then
    echo "Couldn't figure out the test repository's default branch."
    cat $REPO_PROPERTIES
    exit 1
fi

echo "::endgroup::"

echo "::group::Creating OpenPGP keys and configuring policy."

export GNUPGHOME=$(maketemp -d)

gpg --batch --passphrase '' --quick-gen-key '<alice@example.org>' ed25519 sign never
gpg --batch --passphrase '' --quick-gen-key '<bob@example.org>' ed25519 sign never
gpg -k

# Authorize alice (and only alice).
cat >openpgp-policy.toml <<EOF
version = 0
commit_goodlist = []

[authorization."alice"]
sign_commit = true
sign_tag = true
sign_archive = true
add_user = true
retire_user = true
audit = true
keyring = """
$(gpg -a --export alice@example.org)
"""
EOF

echo "::endgroup::"

echo "::group::Add first batch of commits"

git add openpgp-policy.toml

# Add the workflow files.
for f in $FILES
do
    mkdir -p $(dirname $f)
    # By default the workflows uses the actions in
    # sequoia-pgp/authenticate-commits.  But, we don't want to test
    # those.  We want to test the workflows in the current commit.
    sed 's#^\( *uses: \)sequoia-pgp/authenticate-commits@.*$#\1 '"$GITHUB_REPOSITORY@$GITHUB_HEAD_REF#" <"$AUTHENTICATE_COMMITS_REPO/$f" > "$f"
    git add "$f"
done

cat > README.md <<EOF
Testing commit https://github.com/$GITHUB_REPOSITORY/commit/$GITHUB_HEAD_REF .

\`\`\`text
# Commit that we are testing
GITHUB_REPOSITORY=$GITHUB_REPOSITORY
GITHUB_HEAD_REF=$GITHUB_HEAD_REF
# Unit test repository:
OWNER=$OWNER
REPO=$REPO
DEFAULT_BRANCH=$DEFAULT_BRANCH

GITHUB_ACTOR=$GITHUB_ACTOR

$(gpg -k)
\`\`\`
EOF
git add README.md

git commit -m 'Initial commit' -S'<alice@example.org>'

echo foo >> foo
git add foo
git commit -m 'Signed by Alice' -S'<alice@example.org>'

# We have to push to the default branch otherwise the issue_comment
# workflow that we're testing won't run, but the one installed on the
# default branch.  We assume here that the default branch is main.
BASE=$DEFAULT_BRANCH
git push --force origin main:$BASE

GIT_TEST_BASE=$(git rev-parse HEAD)

echo "::endgroup::"

# Create a new commit, push it to a different branch.
echo "::group::Add an unsigned commit"

echo 1 > unsigned
git add unsigned
git commit -m 'Unsigned (bad)' --no-gpg-sign

PR=authenticate-commits-test-0$RANDOM-pr
git push origin main:$PR

echo "::endgroup::"

echo "::group::Open pull request"

# Create a pull request.
BODY=$(maketemp)
# We need to escape newlines.
awk '{ printf("%s\\n", $0) }' >$BODY <<EOF
This is a test, this is only a test!
\`\`\`text
$(git log --pretty=oneline --graph)
\`\`\`

\`\`\`text
gpg -k
$(gpg -k)
\`\`\`
EOF
DATA=$(maketemp)
tee -a $DATA <<EOF
{
      "title":"/authenticate-commits unit test",
      "body":"$(cat $BODY)",
      "head":"$PR",
      "base":"$BASE"
}
EOF


OPEN_PR_RESULT=$(maketemp)
curl --silent --show-error --output $OPEN_PR_RESULT -L \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/repos/$OWNER/$REPO/pulls \
    -d "@$DATA"

PR_URL=$(jq -r ".url" < $OPEN_PR_RESULT)
if test "x$PR_URL" = xnull
then
    echo "Couldn't get PR's URL"
    echo "Server's response:"
    cat "$OPEN_PR_RESULT"
    exit 1
fi
PR_NUMBER=$(jq -r ".number" < $OPEN_PR_RESULT)
if test "x$PR_NUMBER" = xnull
then
    echo "Couldn't get PR's number"
    echo "Server's response:"
    cat "$OPEN_PR_RESULT"
    exit 1
fi

echo "::endgroup::"

echo "Pull request: https://github.com/$OWNER/$REPO/pull/$PR_NUMBER"

# Returns the body of the nth comment (zero-based index).  To return
# the second comment, do:
#
#  wait_for_comment 1
#
# If the comment is not present, this polls for a while.
function wait_for_comment {
    N=$1
    case "$N" in
        [0-9]) :;;
        *)
            echo "Invalid comment number: $N" >&2
            exit 1
            ;;
    esac

    COMMENTS_RESULT=$(maketemp)
    echo "Waiting for comment #$N..." >&2
    for i in $(seq 60 -1 0)
    do
        if test $i -eq 0
        then
            echo "Timeout waiting for comment" >&2
            cat "$COMMENTS_RESULT" >&2
            exit 1
        fi
        sleep 5

        curl --silent --show-error --output "$COMMENTS_RESULT" -L \
             -H "Accept: application/vnd.github+json" \
             -H "Authorization: Bearer $TOKEN" \
             -H "X-GitHub-Api-Version: 2022-11-28" \
             https://api.github.com/repos/$OWNER/$REPO/issues/$PR_NUMBER/comments

        COMMENT=$(jq -r .[$N].body <"$COMMENTS_RESULT")
        if test "x$COMMENT" = xnull
        then
            # The job hasn't completed yet.
            continue
        else
            echo "$COMMENT"
            break
        fi
    done
}

echo "::group::Check that the authenticate-commits action ran, and said no"

COMMENT=$(wait_for_comment 0)
if echo "$COMMENT" | grep -q 'Failed to authenticate commits.'
then
    echo sq-git worked.
else
    echo "Unexpected comment in response to push, did authenticate-commits change?"
    echo "Comment:"
    echo "$COMMENT"
    exit 1
fi

echo "::endgroup::"

echo "::group::Add an unauthorized commit signed by Bob"

git reset --hard $GIT_TEST_BASE
echo 1 > bob
git add bob
git commit -m 'Signed by Bob (bad)' -S'<bob@example.org>'
GIT_TEST_BOB=$(git rev-parse HEAD)

git push --force origin main:$PR

COMMENT=$(wait_for_comment 1)
if echo "$COMMENT" | grep -q 'Failed to authenticate commits.'
then
    echo sq-git worked.
else
    echo "Unexpected comment in response to push, did authenticate-commits change?"
    echo "Comment:"
    echo "$COMMENT"
    exit 1
fi

echo "::endgroup::"

echo "::group::Unauthorized commit by Bob, then authorized commit by Alice"

git reset --hard $GIT_TEST_BOB

echo 1 > alice
git add alice
git commit -m 'Signed by Alice (bad)' -S'<alice@example.org>'

git push --force origin main:$PR

COMMENT=$(wait_for_comment 2)
if echo "$COMMENT" | grep -q 'Failed to authenticate commits.'
then
    echo sq-git worked.
else
    echo "Unexpected comment in response to push, did authenticate-commits change?"
    echo "Comment:"
    echo "$COMMENT"
    exit 1
fi

echo "::endgroup::"

echo "::group::Unauthorized commit by Bob, then authorized merge by Alice"

git reset --hard $GIT_TEST_BASE

git merge --no-ff --no-edit $GIT_TEST_BOB -S'<alice@example.org>'

git push --force origin main:$PR

COMMENT=$(wait_for_comment 3)
if echo "$COMMENT" | grep -q 'authenticates the pull request'
then
    echo sq-git worked.
else
    echo "Unexpected comment in response to push, did authenticate-commits change?"
    echo "Comment:"
    echo "$COMMENT"
    exit 1
fi

echo "::endgroup::"


# Clean up on success.
rm -rf $D
