# Privacy Policy

**Last updated: 2026-07-01**

Session Hawk ("the App") is a companion app for Claude Code. We are committed to protecting your privacy.

### Data Collection

The App does **not** collect, store, or transmit any personal data to external servers.

### How It Works

- The App communicates exclusively over a **local Unix domain socket** on the same Mac, between the app and a hook process invoked by Claude Code.
- All data (agent session events, permission requests, notifications) stays on your device and never leaves it.
- No analytics, telemetry, or crash reporting services are used.
- No third-party SDKs or tracking frameworks are included.

### Local Storage

The App stores minimal preferences (e.g., notification settings) in on-device UserDefaults. This data is never transmitted externally.

### Contact

If you have any questions about this privacy policy, please open an issue at:
https://github.com/jgalea/session-hawk/issues
