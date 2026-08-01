# Appcast / update checks

Redline.app includes a lightweight **Check for Updates** command (Redline menu) that reads an appcast XML feed (`REDLINE_APPCAST_URL`).

## Quick check (built-in)

```bash
export REDLINE_APPCAST_URL="https://your-cdn.com/redline/appcast.xml"
./scripts/run-mac-app.sh
# Redline → Check for Updates…
```

## Appcast example

See `docs/appcast.xml.example`. Host the XML and signed release `.zip` on HTTPS.

## Distribution builds

For automatic background updates in a signed distribution target, wire your preferred update framework against the same appcast URL (`SUFeedURL` / equivalent), enable automatic checks in Info.plist, and sign release artifacts in CI.

The built-in checker is a placeholder until a signed distribution channel exists.
