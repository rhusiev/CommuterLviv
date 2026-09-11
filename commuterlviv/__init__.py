"""The version the whole project ships under.

One number for the service, the web app and the phone app, because they are one
thing to whoever is using them: a leg label that changed in all three is not
three releases. Alpha, so it stays under 1.0 - `check.sh` fails if
`web/package.json` or `mobile/pubspec.yaml` disagrees with this line.
"""
__version__ = "0.4.6"
