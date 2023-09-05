#! /bin/bash

set -e

D=$(dirname $0)

OUTPUT=$(mktemp)

for i in 1
do
    echo "Test #$i"
    $D/../src/format-comment.py \
        --commit-graph $D/data/format-comment/$i-git-log.txt \
        --log $D/data/format-comment/$i-sq-git-log.txt \
        | tee $OUTPUT
    if ! diff -u $OUTPUT $D/data/format-comment/$i-output.txt
    then
        echo
        echo "Error: test #$i failed: output differs from expected output."
    fi
done
