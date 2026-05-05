# Framework Patcher GO
A Magisk/KernelSU/APatch module that patches `/system/framework/services.jar` on-device for mock provider and mock permission bypass logic.

## What it patches
- **Mock Provider**
  - `setIsFromMockProvider(...)` call sites in:
    - `com/android/server/LocationManagerService.smali`
    - `com/android/server/location/MockProvider.smali`
    - `com/android/server/location/provider/MockLocationProvider.smali`
- **Mock Permission**
  - Forces `true` return paths for:
    - `canCallerAccessMockLocation(...)`
    - `noteMockLocationAccess(...)`
    - `checkMockLocationAccess(...)`
    - `noteOp(...)`
    - `noteOpNoThrow(...)`
  - In:
    - `com/android/server/LocationManagerService.smali`
    - `com/android/server/location/AppOpsHelper.smali`
    - `com/android/server/location/injector/SystemAppOpsHelper.smali`

## Usage
1. Install this module from Magisk / KernelSU / APatch app.
2. Reboot after installation.

## Notes
- Your `services.jar` must be deodexed (contain `classes.dex`).
- Patching framework files can cause bootloops on some ROMs. Make sure you know how to remove modules from recovery/safe mode.

## Credits
- Dynamic Installer template and tools.
