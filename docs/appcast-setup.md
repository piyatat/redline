# Appcast / update checks

Redline reads an appcast XML feed from `REDLINE_APPCAST_URL` (HTTPS preferred). In **Redline.app**, use **Redline → Check for Updates…**:

- **Unset / empty** — alert explains how to set the env var (no network call, no example.com fallback).
- **Set** — fetches the feed, compares `shortVersionString` to the running app, and offers **Open Download** when newer.

Launch the app with the env var so the menu command can see it, e.g.:

```bash
export REDLINE_APPCAST_URL="https://your-cdn.com/redline/appcast.xml"
./scripts/run-mac-app.sh
```

## Quick check (CLI / script)

```bash
export REDLINE_APPCAST_URL="https://your-cdn.com/redline/appcast.xml"
# Validate feed URL is reachable, then ship signed artifacts.
curl -sS -I "$REDLINE_APPCAST_URL"
```

## Appcast example

See `docs/appcast.xml.example`. Host the XML and signed release `.zip` on HTTPS.

## Distribution builds

For automatic background updates in a signed distribution target, wire your preferred update framework against the same appcast URL (`SUFeedURL` / equivalent), enable automatic checks in Info.plist, and sign release artifacts in CI. The menu checker is a lightweight manual path until Sparkle (or similar) is adopted.
