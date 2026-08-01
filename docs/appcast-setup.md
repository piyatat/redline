# Appcast / update checks

Redline can read an appcast XML feed via `REDLINE_APPCAST_URL` for future distribution builds. A menu **Check for Updates** command is not wired in the current Redline.app UI — use the env var + scripts below when preparing releases.

## Quick check (CLI / script)

```bash
export REDLINE_APPCAST_URL="https://your-cdn.com/redline/appcast.xml"
# Validate feed URL is reachable, then ship signed artifacts.
curl -sS -I "$REDLINE_APPCAST_URL"
```

## Appcast example

See `docs/appcast.xml.example`. Host the XML and signed release `.zip` on HTTPS.

## Distribution builds

For automatic background updates in a signed distribution target, wire your preferred update framework against the same appcast URL (`SUFeedURL` / equivalent), enable automatic checks in Info.plist, and sign release artifacts in CI.

The in-app checker remains a placeholder until a signed distribution channel exists.
