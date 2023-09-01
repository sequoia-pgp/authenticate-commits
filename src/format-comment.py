#! /usr/bin/python3

import sys
import argparse
import re
import json

def main(argv):
    log = ''
    commit_graph = ''

    argParser = argparse.ArgumentParser()
    argParser.add_argument(
        "-l", "--log", required=True,
        help="file containing the output of 'sq-git log --output-format=json'")
    argParser.add_argument(
        "-c", "--commit-graph", required=True,
        help="file containing the output of 'git log --pretty=oneline --graph'")
    argParser.add_argument(
        "-t", "--trust-root", required=False,
        help="the commit hash of the trust root")

    args = argParser.parse_args()

    # log is an array of dictionaries:
    #
    # [
    #   {
    #     "id": "76eb674aa8919efeb2e43be254f630c807a4b833",
    #     "results": [
    #       {
    #         "Ok": "Neal H. Walfield <neal@pep.foundation> [74E445BA0E15C957]"
    #       }
    #     ]
    #   },
    #   ...
    # ]
    log = json.load(open(args.log, "r"))
    # print(log)

    # We invert log so that we have a dictionary keyed by the commit
    # id.  Note: there may be multiple entries for a given commit id.
    # We need to be careful to merge those entries.
    commits = dict()
    for entry in log:
        id = entry["id"]
        results = entry["results"]

        if id in commits:
            commits[id].append(results)
        else:
            commits[id] = results
    # print(commits)

    commit_id_re = re.compile("^(.*[^0-9a-f])([0-9a-f]{40})[^0-9a-f]")

    # ```text
    # * 76eb674aa8919efeb2e43be254f630c807a4b833 Describe limitations of using GitHub in README.
    # |    - Authorized by Neal H. Walfield <neal@pep.foundation> [74E445BA0E15C957]
    # * d26ec8d256fc2ebe35b618e585ca0fb4df39700a Authorize wiktor to be a project maintainer.
    print("```text")

    commit_graph = open(args.commit_graph, "r")
    for line in commit_graph.readlines():
        line = line.rstrip()
        print(line)

        match = commit_id_re.search(line)
        if match is None:
            continue

        prefix = match.group(1)
        # Replace the * (signifying this commit) with a |.
        prefix = prefix.replace('*', '|', 1) + "  "
        commit_id = match.group(2)

        if commit_id == args.trust_root:
            print(f"{prefix}- Trust root.")

        results = commits.get(commit_id)
        if results is None:
            if commit_id != args.trust_root:
                print(f"{prefix}- Not checked.")
            continue

        # Print the results.
        for result in results:
            msg = result.get('Ok')
            if msg is not None:
                print(f"{prefix}- Authorized by {msg}")
            else:
                msg = result.get('Err')
                if msg is not None:
                    print(f"{prefix}- Error: {msg}")
                else:
                    print(f"{prefix}- Invalid JSON: {result}")

    print("```")

if __name__ == "__main__":
   main(sys.argv[1:])
