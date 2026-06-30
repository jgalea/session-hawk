# Packaging

This repository can now produce a local macOS app bundle from the Swift package without requiring an Xcode project archive.

## Current Shape

- `zsh scripts/package-app.sh` builds `SessionHawkApp`, `SessionHawkHooks`, and `SessionHawkSetup` in release mode.
- The script creates `output/package/Session Hawk.app`.
- The bundle embeds helper binaries inside `Contents/Helpers/` so the app can still locate `SessionHawkHooks` after it leaves the repository checkout.
- The script also creates `output/package/Session Hawk.zip` for local sharing or later notarization.

## Unsigned First

If the machine does not yet have a `Developer ID Application` certificate, the script still works. It produces an unsigned `.app` bundle and `.zip` archive for local inspection.

Check whether signing identities are available with:

```bash
security find-identity -v -p codesigning
```

If that command reports `0 valid identities found`, packaging is limited to unsigned output until the certificate is created in the Apple Developer account and imported into the login keychain.

### "Session Hawk is damaged and can't be opened"

This Gatekeeper error appears when macOS quarantines an unsigned or un-notarized download. There are two workarounds:

**Option 1 — remove quarantine (internal/dev use only):**

```bash
xattr -dr com.apple.quarantine "/Applications/Session Hawk.app"
```

Or right-click the app → **Open** → click **Open** to bypass the block once.

**Option 2 — sign and notarize (required for external distribution):** follow the section below.

## Signing And Notarization

When a signing identity is available, pass it in with environment variables:

```bash
SESSION_HAWK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
zsh scripts/package-app.sh
```

The script signs the helper binaries and app bundle, then also signs the DMG itself (required for notarization). Entitlements are declared in `config/packaging/SessionHawkApp.entitlements`.

If a `notarytool` keychain profile is already stored, the same script notarizes and staples in the correct order (app bundle first so the stapled bundle is embedded in the DMG, then the DMG):

```bash
SESSION_HAWK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
SESSION_HAWK_NOTARY_PROFILE="session-hawk-notary" \
zsh scripts/package-app.sh
```

That path expects `xcrun notarytool store-credentials` to have been run ahead of time.

## Optional Overrides

The script accepts these environment variables:

- `SESSION_HAWK_APP_NAME`
- `SESSION_HAWK_BUNDLE_ID`
- `SESSION_HAWK_VERSION`
- `SESSION_HAWK_BUILD_NUMBER`
- `SESSION_HAWK_PACKAGE_ROOT`
- `SESSION_HAWK_BUNDLE_DIR`
- `SESSION_HAWK_ZIP_PATH`
- `SESSION_HAWK_SIGN_IDENTITY`
- `SESSION_HAWK_NOTARY_PROFILE`
