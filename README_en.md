# Framework Patcher GO

Framework Patcher GO is a Magisk / KernelSU / APatch module that patches `/system/framework/services.jar` directly on-device.

It is mainly designed to apply Mock Provider and Mock Permission bypass patches without using a PC-side Smali patcher workflow.

## Features

### Mock Provider Patch

Patches `setIsFromMockProvider(...)` call sites to prevent locations from being marked as mock locations.

Target files may include:

- `com/android/server/LocationManagerService.smali`
- `com/android/server/location/MockProvider.smali`
- `com/android/server/location/provider/MockLocationProvider.smali`

Depending on the Android version and ROM, not all files will exist. The installer will automatically skip missing files.

### Mock Permission Patch

Patches mock location permission / AppOps related methods to force allowed return paths where applicable.

Target methods may include:

- `canCallerAccessMockLocation(...)`
- `noteMockLocationAccess(...)`
- `checkMockLocationAccess(...)`
- `noteOp(...)`
- `noteOpNoThrow(...)`

Target files may include:

- `com/android/server/LocationManagerService.smali`
- `com/android/server/location/AppOpsHelper.smali`
- `com/android/server/location/injector/SystemAppOpsHelper.smali`

The actual patched files depend on the Android version, ROM implementation, and framework structure.

## Requirements

- Root environment:
  - Magisk
  - KernelSU
  - APatch
- Android system must be fully booted when installing.
- `/system/framework/services.jar` must be deodexed and contain `classes.dex`.
- Enough free space in `/data` or temporary storage for decompiling and rebuilding `services.jar`.

## Installation

1. Install the module using Magisk / KernelSU / APatch.
2. Wait for the installer to decompile, patch, and rebuild `services.jar`.
3. Reboot the device after installation.

## Notes

- Missing target files are normal on newer Android versions or heavily modified ROMs.
- A successful rebuild does not always guarantee boot safety on every ROM.
- Patching framework files may cause bootloops if the ROM has incompatible framework logic.
- Make sure you know how to disable or remove Magisk / KernelSU / APatch modules from recovery, safe mode, or ADB before testing.

## Credits

Special thanks to:

- [sabpprook](https://github.com/sabpprook) — SmaliPatcherEx  
  https://xdaforums.com/t/module-smalipatcherex-1-2-2.4627905/

- [fOmey](https://github.com/fOmey) — Smali Patcher  
  https://xdaforums.com/t/module-smali-patcher-7-4.3680053/

- Dynamic Installer template and related tools.

## Disclaimer

This module modifies Android framework behavior through runtime-mounted framework patches. Use it at your own risk. The author is not responsible for bootloops, data loss, or device issues caused by incompatible ROMs or incorrect usage.
