#!/usr/bin/env bash
# Everything that can be checked without a database, a service or a recording.
# Run it before a commit; it needs nothing but the checkout.
#
# A missing toolchain is reported and stepped over rather than failing the run,
# so someone editing the service need not install Flutter. Nothing is skipped
# silently.
set -u

root=$(cd "$(dirname "$0")" && pwd)
failed=""

step() {
  echo
  echo "== $1"
}

# Runs a command in a directory, and remembers the name if it fails. The name
# is passed in rather than taken from the command, so two npm scripts do not
# both report as "npm"
run() {
  local name=$1 dir=$2
  shift 2
  if ! (cd "$root/$dir" && "$@"); then failed="$failed $name"; fi
}

step "one version, in three trees"
run version . python3 - <<'EOF'
import json, pathlib, re, sys

root = pathlib.Path(".")
want = re.search(r'__version__ = "([^"]+)"',
                 (root / "commuterlviv/__init__.py").read_text()).group(1)
pub = re.search(r"^version: (\S+)\+(\d+)$",
                (root / "mobile/pubspec.yaml").read_text(), re.M)
recipe = (root / "mobile/fdroid/nl.r1a.commuterlviv.yml").read_text()
found = {
    "web/package.json": json.loads((root / "web/package.json").read_text())["version"],
    "mobile/pubspec.yaml": pub.group(1),
    **{f"fdroid versionName #{i}": v for i, v in
       enumerate(re.findall(r"versionName: (\S+)", recipe))},
    **{f"fdroid tag #{i}": v for i, v in
       enumerate(re.findall(r"commit: v(\S+)", recipe))},
    "fdroid CurrentVersion": re.search(r"CurrentVersion: (\S+)", recipe).group(1),
}
bad = {k: v for k, v in found.items() if v != want}
# One build per ABI, coded as Flutter's --split-per-abi codes them
code = int(pub.group(2))
codes_ok = (sorted(map(int, re.findall(r"^ +versionCode: (\d+)", recipe, re.M)))
            == [1000 + code, 2000 + code, 4000 + code]
            and int(re.search(r"CurrentVersionCode: (\d+)", recipe).group(1)) == 4000 + code)
if bad or not codes_ok:
    print(f"commuterlviv/__init__.py says {want}")
    for k, v in bad.items():
        print(f"  {k} says {v}")
    if not codes_ok:
        print(f"  the fdroid version codes are not 1000/2000/4000 + {code}")
    sys.exit(1)
print(f"{want}, build {pub.group(2)}")
EOF

step "python: syntax and undefined names"
if command -v ruff >/dev/null; then
  # Only the rules that mean "this will not run"
  run ruff . ruff check --select E9,F63,F7,F82 commuterlviv
else
  echo "ruff is not installed - falling back to compileall"
  run compileall . python3 -m compileall -q commuterlviv
fi

step "python: the package imports"
run import . python3 -c "import commuterlviv.live.app, commuterlviv.cli"

step "web: types and build"
if command -v npm >/dev/null; then
  [ -d "$root/web/node_modules" ] || run npm-ci web npm ci
  run typecheck web npm run typecheck
  run build web npm run build
else
  echo "npm is not installed - skipped"
fi

step "mobile: analyze and test"
if command -v flutter >/dev/null; then
  run analyze mobile flutter analyze
  run test mobile flutter test
else
  echo "flutter is not on PATH - skipped. /tmp/flutterenv.sh puts it there"
fi

echo
if [ -z "$failed" ]; then
  echo "all checks passed"
else
  echo "failed:$failed"
  exit 1
fi
