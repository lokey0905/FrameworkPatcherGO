if [ "$BOOTMODE" ] && [ "$KSU" ]; then
    ui_print "- Installing from KernelSU app"
elif [ "$BOOTMODE" ] && [ "$APATCH" ]; then
    ui_print "- Installing from APatch app"
elif [ "$BOOTMODE" ] && [ "$MAGISK_VER_CODE" ]; then
    ui_print "- Installing from Magisk app"
else
    ui_print "*********************************************************"
    ui_print "! Installing from recovery is not supported"
    ui_print "! Please install from KernelSU, APatch or Magisk app"
    abort    "*********************************************************"
fi

stock_services="/system/framework/services.jar"
mod_services="$MODPATH$stock_services"

ui_print " "
ui_print "******************************"
ui_print "> Pre-installation check ..."
ui_print "******************************"
real_modpath="$(echo "$MODPATH" | cut -d'_' -f1)/$(echo "$MODPATH" | cut -d'_' -f2 | cut -d'/' -f2)"
if [ -e "$real_modpath$stock_services" ] && [ ! -e "$real_modpath/disable" ]; then
    ui_print "Existing module is running!"
    abort "Please uninstall or disable the existing module before continuing."
else
    ui_print "[ OK ] Checking for existing module."
fi

if (! unzip -l "$stock_services" | grep -q "classes.dex"); then
    abort "/system/framework/services.jar is not deodexed"
else
    ui_print "[ OK ] Checking for deodexed /system/framework/services.jar."
fi

ui_print " "
ui_print "******************************"
ui_print "> Decompiling services.jar ..."
ui_print "******************************"
apktool d "$stock_services" -api "$API" --output "$TMP/services" >/dev/null 2>&1 || abort "Failed to decompile services.jar"

patch_mock_provider() {
    target_file="$1"
    [ -f "$target_file" ] || return 0
    awk '
    {
        line=$0
        if (line ~ /setIsFromMockProvider\(/) {
            reg=""
            if (match(line, /invoke-virtual *\{[^,]+, *([vp][0-9]+)\}/, m)) {
                reg=m[1]
                print "    const/4 " reg ", 0x0"
                print ""
                print line
                print ""
                print "    const/4 " reg ", 0x1"
                patched=1
                next
            }
        }
        print line
    }
    END { if (patched==1) print "# patched_mock_provider" > "/dev/stderr" }
    ' "$target_file" > "$target_file.tmp" && mv "$target_file.tmp" "$target_file"
}

patch_mock_permission() {
    target_file="$1"
    [ -f "$target_file" ] || return 0
    awk '
    BEGIN {
      methods["canCallerAccessMockLocation"]=1
      methods["noteMockLocationAccess"]=1
      methods["checkMockLocationAccess"]=1
      methods["noteOp"]=1
      methods["noteOpNoThrow"]=1
    }
    {
      if (in_method==1) {
        if ($0 ~ /^\.end method/) {
          print "    const/4 v0, 0x1"
          print ""
          print "    return v0"
          print $0
          in_method=0
          patched=1
        }
        next
      }

      print $0
      if ($0 ~ /^\.method /) {
        for (m in methods) {
          if ($0 ~ m"\\(") {
            in_method=1
            break
          }
        }
      }
    }
    END { if (patched==1) print "# patched_mock_permission" > "/dev/stderr" }
    ' "$target_file" > "$target_file.tmp" && mv "$target_file.tmp" "$target_file"
}

ui_print " "
ui_print "******************************"
ui_print "> Patching Mock Provider ..."
ui_print "******************************"
patch_mock_provider "$(find "$TMP/services" -type f -name "LocationManagerService.smali" | head -n1)"
patch_mock_provider "$(find "$TMP/services" -type f -path "*com/android/server/location/MockProvider.smali" | head -n1)"
patch_mock_provider "$(find "$TMP/services" -type f -path "*com/android/server/location/provider/MockLocationProvider.smali" | head -n1)"

ui_print " "
ui_print "******************************"
ui_print "> Patching Mock Permission ..."
ui_print "******************************"
patch_mock_permission "$(find "$TMP/services" -type f -path "*com/android/server/LocationManagerService.smali" | head -n1)"
patch_mock_permission "$(find "$TMP/services" -type f -path "*com/android/server/location/AppOpsHelper.smali" | head -n1)"
patch_mock_permission "$(find "$TMP/services" -type f -path "*com/android/server/location/injector/SystemAppOpsHelper.smali" | head -n1)"

ui_print " "
ui_print "******************************"
ui_print "> Recompiling services.jar ..."
ui_print "******************************"
ui_print "This may take a while, please wait."
apktool b "$TMP/services" -api "$API" --copy-original --output "$TMP/services-patched.jar" >/dev/null 2>&1 || abort "Failed to recompile services.jar"

mkdir -p "$(dirname "$mod_services")"
cp -f "$TMP/services-patched.jar" "$mod_services" || abort "Failed to copy patched services.jar"

ui_print "Some final touches ..."
rm -rf "$MODPATH/func.sh" "$MODPATH/customize.sh" "$MODPATH/dex"
ui_print " "
ui_print "services.jar patched successfully!"
ui_print " "
