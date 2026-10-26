#!/usr/bin/env bash
# Print the tag a pre-release of a commit (default `dev`) goes under:
# `<next version>-dev.<commits since the last release>`, e.g. `0.19.2-dev.37`.
#
# The next version is `commuterlviv/__init__.py`'s when it is bumped and not
# released yet, else that one with its patch raised - a guess, as
# setuptools-scm makes, since the bump decides it. The count only grows along
# `dev`, so GitHub, which sorts releases by their tags as versions, lists the
# newest pre-release first, between the last release and the next.
set -eu

ref=${1:-dev}
version=$(git show "$ref:commuterlviv/__init__.py" | sed -n 's/^__version__ = "\(.*\)"$/\1/p')
last=$(git describe --tags --match 'v[0-9]*' --abbrev=0 "$ref")
since=$(git rev-list --count "$last..$ref")

if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
  IFS=. read -r major minor patch <<<"$version"
  version="$major.$minor.$((patch + 1))"
fi
echo "$version-dev.$since"
