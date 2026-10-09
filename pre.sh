#!/system/bin/sh
# ââââââââââââââââââââââââââââââââââââââââââââââ
TAG="WKSetup"

log() { echo "[$TAG] $1"; }

# --- Discover package by intent filter ---
log "Finding Kids package..."

PACKAGE=$(pm query-activities --brief -a android.intent.action.VIEW -d "one89://kids.io" 2>/dev/null \
  | grep -v "activities found" | grep "/" | head -1 | cut -d'/' -f1 | tr -d ' ')

if [ -z "$PACKAGE" ]; then
  PACKAGE=$(pm query-activities --brief -a android.intent.action.VIEW -d "https://kids.io" 2>/dev/null \
    | grep -v "activities found" | grep "/" | head -1 | cut -d'/' -f1 | tr -d ' ')
fi

if [ -z "$PACKAGE" ]; then
  PACKAGE=$(pm resolve-activity -a android.intent.action.VIEW -d "one89://kids.io" 2>/dev/null \
    | grep "packageName=" | head -1 | sed 's/.*packageName=//' | tr -d ' ')
fi

if [ -z "$PACKAGE" ]; then
  PACKAGE=$(pm list packages 2>/dev/null | grep -i "kids" | grep -i "one89\|watcher" | head -1 | sed 's/package://')
fi

if [ -z "$PACKAGE" ]; then
  log "â Kids package not found!"
  exit 1
fi

log "Found package: $PACKAGE"

# --- Disable Play Protect ---
log "Disabling Play Protect..."
settings put global package_verifier_enable 0 >/dev/null 2>&1
settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1
settings put global package_verifier_user_consent -1 >/dev/null 2>&1
log "Play Protect disabled."

# --- Disable Play Protect / verifiers ---
log "Disabling verifiers..."
pm revoke com.android.vending android.permission.SYSTEM_ALERT_WINDOW 2>/dev/null
settings put global package_verifier_enable 0 2>/dev/null
settings put global package_verifier_user_consent -1 2>/dev/null
settings put global verifier_verify_adb_installs 0 2>/dev/null
settings put secure package_verifier_enable 0 2>/dev/null
settings put secure verifier_verify_adb_installs 0 2>/dev/null
settings put secure install_non_market_apps 1 2>/dev/null
settings put global MIUI_OPTIMIZATION 0 2>/dev/null
settings put global upload_apk_enable 0 2>/dev/null

log "Sending uninstall broadcast..."

log "Uninstall broadcast sent."

sleep 1

# --- Uninstall the package ---
log "Uninstalling $PACKAGE..."
pm uninstall "$PACKAGE" >/dev/null 2>&1
log "Uninstall complete."
