# Releasing Session Hawk

The app must be signed with a **Developer ID Application** certificate and notarized, or downloaders hit Gatekeeper ("damaged / can't be opened"). The packaging script handles signing, notarization, and DMG creation once the prerequisites below are in place.

## One-time prerequisites

1. `brew install create-dmg` (the styled DMG step needs it).
2. A **Developer ID Application** cert in the login keychain. Check with:
   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
   If absent, create one in the Apple Developer portal (RebelCode team `V39FW47X6K`) and install it.
3. A `notarytool` keychain profile (stores the Apple ID + app-specific password once):
   ```sh
   xcrun notarytool store-credentials session-hawk-notary \
     --apple-id <apple-id-email> --team-id V39FW47X6K --password <app-specific-password>
   ```

## Cut a release

```sh
export SESSION_HAWK_SIGN_IDENTITY="Developer ID Application: <name> (V39FW47X6K)"
export SESSION_HAWK_NOTARY_PROFILE="session-hawk-notary"
zsh scripts/package-app.sh
```

This produces a signed, notarized, stapled `Session Hawk.app` and a styled `Session Hawk.dmg`.

Publish it:

```sh
VERSION=1.0.0
gh release create "v$VERSION" "Session Hawk.dmg" \
  --repo jgalea/session-hawk --title "v$VERSION" --notes "..."
```

## Homebrew tap

The cask template is at `packaging/homebrew/session-hawk.rb`. To publish the tap:

1. Create the tap repo `jgalea/homebrew-session-hawk` with the cask at `Casks/session-hawk.rb`.
2. Set the cask `version` and `sha256` (`shasum -a 256 "Session Hawk.dmg"`) to the released DMG.
3. Users then install with:
   ```sh
   brew tap jgalea/session-hawk
   brew install --cask session-hawk
   ```

Until a notarized release exists, do not publish the tap — an unsigned cask gives users Gatekeeper errors that look like a broken app.
