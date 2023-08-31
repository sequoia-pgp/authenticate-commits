#! /bin/bash

# This script is run in the context of the sq-git docker image.  This
# means that we don't have access to many tools.  In particular, the
# sq-git image does not include curl, or jq.

echo ::group::env
env | sort
echo ::endgroup::

set -ex

if test "x$BASE_SHA" = x
then
    echo "BASE_SHA not set."
    exit 1
fi

if test "x$HEAD_SHA" = x
then
    echo "HEAD_SHA not set."
    exit 1
fi

# Persist state to /github/home, which is exposed as
# "$RUNNER_TEMP/_github_home" in other steps.
RESULTS=/github/home/authenticate-commits-results
mkdir -p "$RESULTS"

echo ::group::sq-git policy describe

SQ_GIT_POLICY=$RESULTS/sq-git-policy-describe.json
SQ_GIT_POLICY_STDERR=$RESULTS/sq-git-policy-describe.err

sq-git policy describe --output-format=json \
       2>$SQ_GIT_POLICY_STDERR \
       | tee -a $SQ_GIT_POLICY
echo; echo ::endgroup::

echo ::group::sq-git log

SQ_GIT_LOG=$RESULTS/sq-git-log.json
SQ_GIT_LOG_STDERR=$RESULTS/sq-git-log.err

sq-git log --output-format=json --keep-going \
       --trust-root "$BASE_SHA" "$HEAD_SHA" \
       2>$SQ_GIT_LOG_STDERR \
       | tee -a $SQ_GIT_LOG
echo; echo ::endgroup::
