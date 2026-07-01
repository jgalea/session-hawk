# Releasing

Versioning and release-notes conventions for Session Hawk. For the actual build/sign/publish commands, see [RELEASE.md](../RELEASE.md).

## Versioning

Follow [Semantic Versioning](https://semver.org/):

- **Patch** (0.1.x): bug fixes, doc updates, small improvements
- **Minor** (0.x.0): new features, non-breaking changes
- **Major** (x.0.0): breaking changes

## Checklist

1. **Confirm target**: ensure all intended changes are merged to `main`.
2. **Build, sign (if configured), and publish**: follow [RELEASE.md](../RELEASE.md) — `zsh scripts/package-app.sh` produces `output/package/Session Hawk.dmg` and `.zip`, then `gh release create`.
3. **Write release notes** using the format below.
4. **Verify**: open the release page and confirm assets are downloadable.

## Release Notes Format

```markdown
## Session Hawk v<version> — <Title>

### Changes since v<prev>

- <emoji> **Category**: description (#PR)

---

## Installation

<< See "Installation Section" below >>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Change categories

| Emoji | Category | When to use |
|-------|----------|-------------|
| ✨ | Feature | New user-facing functionality |
| 🐛 | Fix | Bug fix |
| 📸/📋 | Docs | Documentation changes |
| ♻️ | Refactor | Code restructuring |
| 🏗️ | Infra | Build, CI, packaging changes |

## Installation Section

Use the unsigned version below until the release is signed and notarized (see [RELEASE.md](../RELEASE.md) prerequisites); switch to the signed version once it is.

**Unsigned:**

```markdown
## Installation

1. Download **Session Hawk.dmg**, open it, and drag **Session Hawk** to **Applications**.
2. Since this is an unsigned app, macOS will show **"Session Hawk is damaged"** when you try to open it. Run this command in Terminal to fix it:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Session Hawk.app"
   ```

3. Requirements: **macOS 14+**, **Apple Silicon**.
```

**Signed and notarized:**

```markdown
## Installation

1. Download **Session Hawk.dmg**, open it, and drag **Session Hawk** to **Applications**.
2. This build is signed and notarized with Apple Developer ID — open it directly, no security workaround needed.
3. Requirements: **macOS 14+**, **Apple Silicon**.

Or via Homebrew:

```bash
brew tap jgalea/session-hawk
brew install --cask session-hawk
```
```

## Assets

Every release ships two artifacts:

| File | Purpose |
|------|---------|
| `Session Hawk.dmg` | Styled disk image with drag-to-Applications |
| `Session Hawk.zip` | Plain zip for automation / CI downloads |
