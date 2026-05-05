# Framework Patcher GO

Framework Patcher GO 是一個 Magisk / KernelSU / APatch 模組，可在手機端直接修補 `/system/framework/services.jar`。

本模組主要用於套用 Mock Provider 與 Mock Permission 相關繞過修補，不需要透過電腦端 Smali Patcher 流程手動反編譯與重編譯。

## 功能

### Mock Provider 修補

修補 `setIsFromMockProvider(...)` 相關呼叫，避免定位被標記為 mock location。

可能修補的目標檔案包含：

- `com/android/server/LocationManagerService.smali`
- `com/android/server/location/MockProvider.smali`
- `com/android/server/location/provider/MockLocationProvider.smali`

不同 Android 版本與 ROM 架構可能會有不同路徑。若部分檔案不存在，安裝器會自動略過，這是正常情況。

### Mock Permission 修補

修補 mock location permission / AppOps 相關方法，使符合條件的方法回傳允許狀態。

可能修補的目標方法包含：

- `canCallerAccessMockLocation(...)`
- `noteMockLocationAccess(...)`
- `checkMockLocationAccess(...)`
- `noteOp(...)`
- `noteOpNoThrow(...)`

可能修補的目標檔案包含：

- `com/android/server/LocationManagerService.smali`
- `com/android/server/location/AppOpsHelper.smali`
- `com/android/server/location/injector/SystemAppOpsHelper.smali`

實際能修補到哪些檔案，會依 Android 版本、ROM 實作與 framework 結構而不同。

## 需求

- Root 環境：
  - Magisk
  - KernelSU
  - APatch
- 安裝時 Android 系統必須已正常開機。
- `/system/framework/services.jar` 必須是 deodexed，且內含 `classes.dex`。
- `/data` 或暫存空間需要有足夠容量，用於反編譯與重新編譯 `services.jar`。

## 安裝方式

1. 使用 Magisk / KernelSU / APatch 安裝本模組。
2. 等待安裝器自動反編譯、修補並重編譯 `services.jar`。
3. 安裝完成後重開機。

## 注意事項

- 新版 Android 或深度客製 ROM 中，部分目標檔案不存在是正常情況。
- `services.jar` 成功重編譯不代表所有 ROM 都能安全開機。
- 修補 framework 檔案有機率造成 bootloop。
- 測試前請先確認自己知道如何從 recovery、安全模式或 ADB 停用 / 移除 Magisk、KernelSU、APatch 模組。

## 致謝

特別感謝：

- [sabpprook](https://github.com/sabpprook) — SmaliPatcherEx  
  https://xdaforums.com/t/module-smalipatcherex-1-2-2.4627905/

- [fOmey](https://github.com/fOmey) — Smali Patcher  
  https://xdaforums.com/t/module-smali-patcher-7-4.3680053/

- Dynamic Installer template 與相關工具。

## 免責聲明

本模組會透過模組掛載方式修改 Android framework 行為。使用前請自行評估風險。若因 ROM 不相容、修補失敗或使用方式錯誤導致 bootloop、資料遺失或裝置異常，作者不承擔相關責任。
