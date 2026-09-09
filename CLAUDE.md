Read `HANDOFF.md` first. It says what this project is, which document answers
which question, what state the work is in, and what to do next.

Bump the version with every substantial change: `commuterlviv/__init__.py` is the
source, `web/package.json`, `mobile/pubspec.yaml` and the F-Droid recipe repeat
it, and `check.sh` fails if they drift. Alpha, so 0.X.X. When the phone app
changed, rebuild it with `deploy/release-apk.sh` so `<site>/download/` is the
new build.

`PLAN.md` is the working plan for the approach comparison. Reread it after every
compaction, mark each item as it lands, and when something is dropped keep the
reason.
