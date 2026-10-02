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

step "versions: the server's, and the app's at or behind it"
run version . python3 - <<'EOF'
import json, pathlib, re, sys

root = pathlib.Path(".")
server = re.search(r'__version__ = "([^"]+)"',
                   (root / "commuterlviv/__init__.py").read_text()).group(1)
pub = re.search(r"^version: (\S+)\+(\d+)$",
                (root / "mobile/pubspec.yaml").read_text(), re.M)
app = pub.group(1)
recipe = (root / "mobile/fdroid/nl.r1a.commuterlviv.yml").read_text()
web = json.loads((root / "web/package.json").read_text())["version"]
bad = [f"web/package.json says {web}, the server {server}"] if web != server else []
recipe_versions = {
    **{f"fdroid versionName #{i}": v for i, v in
       enumerate(re.findall(r"versionName: (\S+)", recipe))},
    **{f"fdroid tag #{i}": v for i, v in
       enumerate(re.findall(r"commit: v(\S+)", recipe))},
    "fdroid CurrentVersion": re.search(r"CurrentVersion: (\S+)", recipe).group(1),
}
bad += [f"{k} says {v}, the pubspec {app}" for k, v in recipe_versions.items() if v != app]
# One build per ABI, coded as Flutter's --split-per-abi codes them
code = int(pub.group(2))
if (sorted(map(int, re.findall(r"^ +versionCode: (\d+)", recipe, re.M)))
        != [1000 + code, 2000 + code, 4000 + code]
        or int(re.search(r"CurrentVersionCode: (\d+)", recipe).group(1)) != 4000 + code):
    bad.append(f"the fdroid version codes are not 1000/2000/4000 + {code}")
if [*map(int, app.split("."))] > [*map(int, server.split("."))]:
    bad.append(f"the app's {app} is ahead of the server's {server}")
if bad:
    print(*bad, sep="\n")
    sys.exit(1)
print(f"server {server}, app {app} build {code}")
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
