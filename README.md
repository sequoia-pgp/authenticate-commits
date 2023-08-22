# Authenticate Commits

Authenticates a merge request by checking that the commits are
authorized by the repository's embedded signing policy.

This action is intended for use with projects that use [Sequoia
git](https://gitlab.com/sequoia-pgp/sequoia-git).  Sequoia git is a
framework that can improve a project's supply chain security.  It
defines a set of semantics for authorizing commits, and a tool to
check that a policy holds.  Using Sequoia git allows downstream users
to check that a new version of the software is derived from an older
version, which can prevent the use of versions that include
modifications that were not authorized by the project's maintainers.

To use Sequoia git, you add a policy file to the root of a git
repository (openpgp-policy.toml), and authorize OpenPGP certificates
to make different types of changes.  A commit is considered authorized
if the commit has a valid signature, and at least one immediate
parent's policy allows the signer to make that type of change.
Downstream users check that a new version is authorized by using
sq-git to verify that there is a chain of trust from a known-good old
version to the version they are interested in.

See the [project's
documentation](https://gitlab.com/sequoia-pgp/sequoia-git/-/blob/main/README.md)
for more details.

## Example

To authenticate the commits in a pull request, add
`.github/workflows/authenticate-commits.yml` to your repository with
the following contents:

```yaml
name: authenticate-commits
on:
  pull_request:
    types: [opened, reopened, synchronize]
jobs:
  authenticate-commits:
    runs-on: ubuntu-latest

    permissions:
      contents: read
      pull-requests: write
      issues: write

    steps:
      - name: Authenticating commits
        uses: sequoia-pgp/authenticate-commits@main
```

This checks that each commit in the pull request can be authenticated
by at least one of its parents.  The results are posted as a comment
to the pull request.

