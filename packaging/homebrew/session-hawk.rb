# Homebrew cask for Session Hawk — goes in the tap repo jgalea/homebrew-session-hawk
# at Casks/session-hawk.rb. Fill version + sha256 after the GitHub release is cut.
#
# Install flow once published:
#   brew tap jgalea/session-hawk
#   brew install --cask session-hawk
#
# NOTE: until a Developer ID-notarized build exists, this app is ad-hoc signed.
# Unsigned/ad-hoc casks trip Gatekeeper; either notarize (preferred) or document
# the right-click-Open / `xattr -dr com.apple.quarantine` step in the repo README.

cask "session-hawk" do
  version "1.0.0"
  sha256 "REPLACE_WITH_DMG_SHA256" # shasum -a 256 "Session Hawk.dmg"

  url "https://github.com/jgalea/session-hawk/releases/download/v#{version}/Session.Hawk.dmg",
      verified: "github.com/jgalea/session-hawk/"
  name "Session Hawk"
  desc "Lean, local-first macOS notch companion for Claude Code"
  homepage "https://github.com/jgalea/session-hawk"

  depends_on macos: ">= :sonoma" # macOS 14+

  app "Session Hawk.app"

  zap trash: [
    "~/Library/Application Support/SessionHawk",
    "~/Library/Preferences/com.jeangalea.sessionhawk.plist",
    "~/Library/Caches/com.jeangalea.sessionhawk",
  ]
end
