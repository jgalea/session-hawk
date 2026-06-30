#!/bin/zsh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Session Hawk smoke runs only on macOS." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

timestamp="$(date +%Y%m%d-%H%M%S)"
artifact_dir="${SESSION_HAWK_HARNESS_ARTIFACT_DIR:-$repo_root/output/harness/smoke-$timestamp}"

export SESSION_HAWK_HARNESS_SCENARIO="${SESSION_HAWK_HARNESS_SCENARIO:-approvalCard}"
export SESSION_HAWK_HARNESS_PRESENT_OVERLAY="${SESSION_HAWK_HARNESS_PRESENT_OVERLAY:-1}"
export SESSION_HAWK_HARNESS_START_BRIDGE="${SESSION_HAWK_HARNESS_START_BRIDGE:-0}"
export SESSION_HAWK_HARNESS_BOOT_ANIMATION="${SESSION_HAWK_HARNESS_BOOT_ANIMATION:-0}"
export SESSION_HAWK_HARNESS_CAPTURE_DELAY_SECONDS="${SESSION_HAWK_HARNESS_CAPTURE_DELAY_SECONDS:-1}"
export SESSION_HAWK_HARNESS_AUTO_EXIT_SECONDS="${SESSION_HAWK_HARNESS_AUTO_EXIT_SECONDS:-2}"
export SESSION_HAWK_HARNESS_ARTIFACT_DIR="$artifact_dir"

mkdir -p "$artifact_dir"

echo "Launching SessionHawkApp smoke scenario '${SESSION_HAWK_HARNESS_SCENARIO}' for ${SESSION_HAWK_HARNESS_AUTO_EXIT_SECONDS}s"
swift run SessionHawkApp

report_path="$artifact_dir/report.json"
if [[ ! -f "$report_path" ]]; then
    echo "Smoke failed: missing harness report at $report_path" >&2
    exit 1
fi

png_count="$(find "$artifact_dir" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
if [[ "$png_count" -eq 0 ]]; then
    echo "Smoke failed: no PNG artifacts captured in $artifact_dir" >&2
    exit 1
fi

ax_count="$(find "$artifact_dir" -maxdepth 1 -name '*.ax.json' | wc -l | tr -d ' ')"
if [[ "$ax_count" -eq 0 ]]; then
    echo "Smoke failed: no accessibility artifacts captured in $artifact_dir" >&2
    exit 1
fi

python3 - "$report_path" <<'PY'
import subprocess
import sys

subprocess.run(
    [sys.executable, "scripts/validate-harness-artifacts.py", sys.argv[1]],
    check=True,
)
PY

echo "Artifacts written to $artifact_dir"
echo "SessionHawkApp smoke passed"
