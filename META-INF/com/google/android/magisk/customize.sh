BOOT_COMPLETED="$(getprop sys.boot_completed 2>/dev/null)"
MAGISK_PATH="$(command -v magisk 2>/dev/null)"

if [ -z "$MAGISK_VER_CODE" ] && [ -n "$MAGISK_PATH" ]; then
    MAGISK_VER_CODE="$($MAGISK_PATH -V 2>/dev/null | head -n 1)"
fi

ui_print "[ DBG ] BOOTMODE=$BOOTMODE"
ui_print "[ DBG ] KSU=$KSU"
ui_print "[ DBG ] APATCH=$APATCH"
ui_print "[ DBG ] MAGISK_VER_CODE=$MAGISK_VER_CODE"
ui_print "[ DBG ] BOOT_COMPLETED=$BOOT_COMPLETED"
ui_print "[ DBG ] MAGISK_PATH=$MAGISK_PATH"

if [ "$BOOT_COMPLETED" != "1" ]; then
    ui_print "*********************************************************"
    ui_print "! Installing from recovery is not supported"
    ui_print "! Please install from KernelSU, APatch or Magisk app/CLI"
    abort "*********************************************************"
fi

if [ -n "$KSU" ]; then
    ui_print "- Installing from KernelSU app/CLI"
elif [ -n "$APATCH" ]; then
    ui_print "- Installing from APatch app/CLI"
elif [ -n "$MAGISK_VER_CODE" ] || [ -n "$MAGISK_PATH" ]; then
    ui_print "- Installing from Magisk app/CLI"
else
    abort "No supported root manager detected"
fi

if [ -f "$MODPATH/func.sh" ]; then
    . "$MODPATH/func.sh"
fi

stock_services="/system/framework/services.jar"
mod_services="$MODPATH$stock_services"
patched_count=0

ui_print " "
ui_print "******************************"
ui_print "> Pre-installation check ..."
ui_print "******************************"

module_id="${MODPATH##*/}"
real_modpath="/data/adb/modules/$module_id"

ui_print "[ DBG ] MODPATH=$MODPATH"
ui_print "[ DBG ] module_id=$module_id"
ui_print "[ DBG ] real_modpath=$real_modpath"
ui_print "[ DBG ] stock_services=$stock_services"

if [ -e "$real_modpath$stock_services" ] && [ ! -e "$real_modpath/disable" ]; then
    ui_print "Existing module is running!"
    abort "Please uninstall or disable the existing module before continuing."
else
    ui_print "[ OK ] Checking for existing module."
fi

if [ ! -f "$stock_services" ]; then
    abort "$stock_services not found"
fi

if unzip -l "$stock_services" 2>/dev/null | grep -q "classes.dex"; then
    ui_print "[ OK ] Checking for deodexed /system/framework/services.jar."
else
    abort "/system/framework/services.jar is not deodexed or unzip failed"
fi

ui_print " "
ui_print "******************************"
ui_print "> Decompiling services.jar ..."
ui_print "******************************"
apktool d "$stock_services" -api "$API" --output "$TMP/services" || abort "Failed to decompile services.jar"

patch_mock_provider() {
    target_file="$1"
    [ -f "$target_file" ] || return 1
    tmp_file="$target_file.tmp"
    changed=1

    rm -f "$tmp_file"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *setIsFromMockProvider\(*)
                reg="$(printf '%s\n' "$line" | sed -nE 's/.*invoke-virtual[[:space:]]*\{[^,]+,[[:space:]]*([vp][0-9]+)\}.*/\1/p')"
                if [ -n "$reg" ]; then
                    printf '    const/4 %s, 0x0\n\n' "$reg" >> "$tmp_file"
                    printf '%s\n\n' "$line" >> "$tmp_file"
                    printf '    const/4 %s, 0x1\n' "$reg" >> "$tmp_file"
                    changed=0
                    continue
                fi
                ;;
        esac
        printf '%s\n' "$line" >> "$tmp_file"
    done < "$target_file"

    mv "$tmp_file" "$target_file"
    return $changed
}

emit_return_value() {
    # Mock permission methods in Location/AppOps helpers are expected to return boolean.
    # v0 is made available by forcing .locals >= 1 before insertion.
    printf '    const/4 v0, 0x1\n\n'
    printf '    return v0\n'
}

patch_mock_permission() {
    target_file="$1"
    [ -f "$target_file" ] || return 1
    tmp_file="$target_file.tmp"
    changed=1
    in_target=0
    inserted=0
    saw_locals=0

    rm -f "$tmp_file"
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$in_target" = "0" ]; then
            printf '%s\n' "$line" >> "$tmp_file"
            case "$line" in
                *"method private canCallerAccessMockLocation("*|*"method public noteMockLocationAccess("*|*"method public checkMockLocationAccess("*)
                    case "$line" in
                        *")Z")
                            in_target=1
                            inserted=0
                            saw_locals=0
                            ;;
                        *)
                            ui_print "[ SKIP ] Unsupported return type: $line"
                            ;;
                    esac
                    ;;
            esac
            continue
        fi

        # Inside target method: keep method header/debug directives, then replace body.
        if [ "$inserted" = "0" ]; then
            case "$line" in
                *".locals "*)
                    saw_locals=1
                    locals_num="$(printf '%s\n' "$line" | sed -nE 's/^[[:space:]]*\.locals[[:space:]]+([0-9]+).*/\1/p')"
                    if [ -n "$locals_num" ] && [ "$locals_num" -lt 1 ]; then
                        printf '    .locals 1\n' >> "$tmp_file"
                    else
                        printf '%s\n' "$line" >> "$tmp_file"
                    fi
                    continue
                    ;;
                *".registers "*)
                    saw_locals=1
                    printf '%s\n' "$line" >> "$tmp_file"
                    continue
                    ;;
                ""|[[:space:]]|[[:space:]][[:space:]]|[[:space:]][[:space:]][[:space:]]|[[:space:]][[:space:]][[:space:]][[:space:]])
                    printf '%s\n' "$line" >> "$tmp_file"
                    continue
                    ;;
                [[:space:]].*|.*)
                    # Keep smali directives/comments before first instruction, such as .param, .annotation, .line.
                    first_char="$(printf '%s' "$line" | sed -nE 's/^[[:space:]]*([^[:space:]]).*$/\1/p')"
                    if [ "$first_char" = "." ] || [ "$first_char" = "#" ]; then
                        printf '%s\n' "$line" >> "$tmp_file"
                        continue
                    fi
                    ;;
            esac

            # First real instruction or label: inject replacement body and drop the original body.
            if [ "$saw_locals" = "0" ]; then
                printf '    .locals 1\n' >> "$tmp_file"
            fi
            emit_return_value >> "$tmp_file"
            inserted=1
            changed=0
            continue
        fi

        case "$line" in
            *".end method"*)
                printf '%s\n' "$line" >> "$tmp_file"
                in_target=0
                inserted=0
                saw_locals=0
                ;;
            *)
                continue
                ;;
        esac
    done < "$target_file"

    mv "$tmp_file" "$target_file"
    return $changed
}

patch_if_exists() {
    file_path="$1"
    patch_type="$2"
    if [ -n "$file_path" ] && [ -f "$file_path" ]; then
        if [ "$patch_type" = "provider" ]; then
            if patch_mock_provider "$file_path"; then
                patched_count=$((patched_count + 1))
                ui_print "[ OK ] Patched provider: $file_path"
            else
                ui_print "[ SKIP ] Pattern not found/provider unchanged: $file_path"
            fi
        else
            if patch_mock_permission "$file_path"; then
                patched_count=$((patched_count + 1))
                ui_print "[ OK ] Patched permission: $file_path"
            else
                ui_print "[ SKIP ] Pattern not found/permission unchanged: $file_path"
            fi
        fi
    else
        ui_print "[ SKIP ] Not found: $file_path"
    fi
}

ui_print " "
ui_print "******************************"
ui_print "> Patching Mock Provider ..."
ui_print "******************************"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/LocationManagerService.smali" | head -n1)" "provider"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/MockProvider.smali" | head -n1)" "provider"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/provider/MockLocationProvider.smali" | head -n1)" "provider"

ui_print " "
ui_print "******************************"
ui_print "> Patching Mock Permission ..."
ui_print "******************************"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/LocationManagerService.smali" | head -n1)" "permission"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/AppOpsHelper.smali" | head -n1)" "permission"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/injector/SystemAppOpsHelper.smali" | head -n1)" "permission"

if [ "$patched_count" -eq 0 ]; then
    abort "No target smali pattern found in services.jar. Nothing patched."
fi

ui_print " "
ui_print "******************************"
ui_print "> Recompiling services.jar ..."
ui_print "******************************"
ui_print "This may take a while, please wait."

BUILD_LOG="$TMP/fpgo_apktool_build.log"
apktool b "$TMP/services" -api "$API" --copy-original --output "$TMP/services-patched.jar" > "$BUILD_LOG" 2>&1
BUILD_RC=$?
while IFS= read -r log_line || [ -n "$log_line" ]; do
    ui_print "$log_line"
done < "$BUILD_LOG"

if [ "$BUILD_RC" != "0" ]; then
    cp -f "$BUILD_LOG" /data/local/tmp/fpgo_apktool_build.log 2>/dev/null
    abort "Failed to recompile services.jar. Log saved to /data/local/tmp/fpgo_apktool_build.log"
fi

mkdir -p "$(dirname "$mod_services")"
cp -f "$TMP/services-patched.jar" "$mod_services" || abort "Failed to copy patched services.jar"

ui_print "Some final touches ..."
rm -rf "$MODPATH/func.sh" "$MODPATH/customize.sh" "$MODPATH/dex"
ui_print " "
ui_print "services.jar patched successfully!"
ui_print " "
