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
DEBUG_DIR="/data/local/tmp/fpgo_debug"

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

rm -rf "$DEBUG_DIR"
mkdir -p "$DEBUG_DIR" 2>/dev/null

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
                # C# regex equivalent: invoke-virtual ?{\w+, ?(\w+)}
                reg="$(printf '%s\n' "$line" | sed -nE 's/.*invoke-virtual[[:space:]]*\{[[:alnum:]_]+,[[:space:]]*([[:alnum:]_]+)\}.*/\1/p')"
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

is_csharp_mock_permission_method() {
    line="$1"
    case "$line" in
        *".method private canCallerAccessMockLocation("*) return 0 ;;
        *".method public noteMockLocationAccess("*) return 0 ;;
        *".method public checkMockLocationAccess("*) return 0 ;;
        *".method public noteOp("*) return 0 ;;
        *".method public noteOpNoThrow("*) return 0 ;;
    esac
    return 1
}

method_name_for_log() {
    line="$1"
    case "$line" in
        *"canCallerAccessMockLocation("*) printf 'canCallerAccessMockLocation'; return 0 ;;
        *"noteMockLocationAccess("*) printf 'noteMockLocationAccess'; return 0 ;;
        *"checkMockLocationAccess("*) printf 'checkMockLocationAccess'; return 0 ;;
        *"noteOpNoThrow("*) printf 'noteOpNoThrow'; return 0 ;;
        *"noteOp("*) printf 'noteOp'; return 0 ;;
    esac
    printf 'unknown'
}

method_ret_for_log() {
    line="$1"
    ret="${line##*)}"
    printf '%s' "$ret"
}

# C#-compatible logic:
#   1. Match the same exact method-line substrings as SmaliPatcherEx.
#   2. Keep the method line and the next two lines exactly as-is.
#   3. Insert const/4 v0, 0x1 + return v0.
#   4. Drop everything until .end method, then keep .end method.
# Difference from previous enhanced shell version:
#   - Do NOT rewrite/increase .registers.
#   - Do NOT keep extra .param/.annotation lines before injection.
# This makes the generated smali much closer to the known-good C# output.
patch_mock_permission_csharp_compat() {
    target_file="$1"
    [ -f "$target_file" ] || return 1
    tmp_file="$target_file.tmp"
    changed=1

    rm -f "$tmp_file"
    while IFS= read -r line || [ -n "$line" ]; do
        if is_csharp_mock_permission_method "$line"; then
            mname="$(method_name_for_log "$line")"
            mret="$(method_ret_for_log "$line")"
            ui_print "[ DBG ] C#-compat permission method: $mname return=$mret"

            printf '%s\n' "$line" >> "$tmp_file"

            if IFS= read -r keep1; then
                printf '%s\n' "$keep1" >> "$tmp_file"
            fi
            if IFS= read -r keep2; then
                printf '%s\n' "$keep2" >> "$tmp_file"
            fi

            case "$mret" in
                Z|I)
                    printf '    const/4 v0, 0x1\n\n' >> "$tmp_file"
                    printf '    return v0\n' >> "$tmp_file"
                    ;;
                V)
                    # Not expected for the known Mock Permission targets on this ROM.
                    # Kept to avoid producing invalid smali if an OEM changes a method to void.
                    printf '    return-void\n' >> "$tmp_file"
                    ;;
                *)
                    ui_print "[ WARN ] Unsupported return type for $mname: $mret ; using C# default return v0"
                    printf '    const/4 v0, 0x1\n\n' >> "$tmp_file"
                    printf '    return v0\n' >> "$tmp_file"
                    ;;
            esac

            while IFS= read -r line || [ -n "$line" ]; do
                case "$line" in
                    *".end method"*)
                        printf '%s\n' "$line" >> "$tmp_file"
                        break
                        ;;
                esac
            done

            changed=0
            ui_print "[ OK ] Patched C#-compat permission method: $mname"
            continue
        fi

        printf '%s\n' "$line" >> "$tmp_file"
    done < "$target_file"

    mv "$tmp_file" "$target_file"
    return $changed
}

copy_debug_smali() {
    src="$1"
    tag="$2"
    [ -f "$src" ] || return 0
    base="$(basename "$src")"
    cp -f "$src" "$DEBUG_DIR/${tag}_${base}" 2>/dev/null
}

patch_if_exists() {
    file_path="$1"
    patch_type="$2"
    if [ -n "$file_path" ] && [ -f "$file_path" ]; then
        if [ "$patch_type" = "provider" ]; then
            copy_debug_smali "$file_path" "before_provider"
            if patch_mock_provider "$file_path"; then
                patched_count=$((patched_count + 1))
                copy_debug_smali "$file_path" "after_provider"
                ui_print "[ OK ] Patched provider: $file_path"
            else
                ui_print "[ SKIP ] Pattern not found/provider unchanged: $file_path"
            fi
        else
            copy_debug_smali "$file_path" "before_permission"
            if patch_mock_permission_csharp_compat "$file_path"; then
                patched_count=$((patched_count + 1))
                copy_debug_smali "$file_path" "after_permission"
                ui_print "[ OK ] Patched C#-compat permission: $file_path"
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
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/LocationManagerService.smali" | head -n1)" "provider"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/MockProvider.smali" | head -n1)" "provider"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/provider/MockLocationProvider.smali" | head -n1)" "provider"

ui_print " "
ui_print "******************************"
ui_print "> Patching Mock Permission ..."
ui_print "******************************"
ui_print "[ INFO ] Using C#-compatible method replacement logic."
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/LocationManagerService.smali" | head -n1)" "permission"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/LocationManagerService.smali" | head -n1)" "permission"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/AppOpsHelper.smali" | head -n1)" "permission"
patch_if_exists "$(find "$TMP/services" -type f -path "*com/android/server/location/injector/AppOpsHelper.smali" | head -n1)" "permission"
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
cp -f "$BUILD_LOG" "$DEBUG_DIR/fpgo_apktool_build.log" 2>/dev/null

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
ui_print "[ INFO ] Debug smali/logs saved to $DEBUG_DIR"
ui_print " "
