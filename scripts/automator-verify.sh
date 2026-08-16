#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPO_DIR="${VOLTAIRE_REPO_DIR:-${SCRIPT_DIR:h}}"
readonly PROJECT="$REPO_DIR/Voltaire.xcodeproj"
readonly SCHEME="Voltaire"
readonly BUNDLE_ID="com.voltaire.reader"
readonly SIMULATOR_ID="${VOLTAIRE_SIMULATOR_ID:-D27D8620-F123-4944-945F-09B002DD088C}"
readonly RUN_STAMP="$(date '+%Y-%m-%d-%H%M%S')"
readonly DERIVED_DATA="/tmp/VoltaireAutomator-$RUN_STAMP"
readonly EVIDENCE_DIR="$REPO_DIR/artifacts/automator"
readonly RESULT_BUNDLE="$EVIDENCE_DIR/Voltaire-$RUN_STAMP.xcresult"
readonly LOG_FILE="$EVIDENCE_DIR/Voltaire-$RUN_STAMP.log"
readonly STATUS_FILE="$EVIDENCE_DIR/latest-status.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$LOG_FILE") 2>&1

write_status() {
    printf '%s\n' "$1" > "$STATUS_FILE"
}

on_error() {
    local exit_code=$?
    write_status "FAILED — $RUN_STAMP — see $LOG_FILE"
    exit "$exit_code"
}

trap on_error ERR

write_status "RUNNING — $RUN_STAMP"
cd "$REPO_DIR"

if ! xcrun simctl list devices | grep -q "$SIMULATOR_ID"; then
    echo "Required iPad simulator not found: $SIMULATOR_ID"
    exit 2
fi

xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$RESULT_BUNDLE" \
    CODE_SIGNING_ALLOWED=NO \
    test

readonly APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Voltaire.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Built app was not found at $APP_PATH"
    exit 3
fi

xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" "$BUNDLE_ID"

write_status "SIMULATOR VERIFIED — $RUN_STAMP — $RESULT_BUNDLE"
echo "Voltaire simulator verification passed."
echo "Physical iPad narration and visual acceptance remain separate."
echo "Result: $RESULT_BUNDLE"
echo "Log: $LOG_FILE"
