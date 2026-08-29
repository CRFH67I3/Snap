# 将 Snap 编译、打包并安装到 iPhone

本文记录本项目在实体 iPhone 上的本地开发部署流程。它使用本机的 Apple Development / Personal Team 签名，不上传源码、签名产物、证书或设备标识。

## 本次环境与结果

- 工程：`Snap.xcodeproj`，Scheme：`Snap`，主应用 Bundle ID：`com.tao.Snap`。
- 工具链：Xcode 27.0 Beta（Build 27A5228h）。
- 目标设备：已连接的 iPhone 16 Pro（iOS 27.0）。
- 2026-08-30 起：工程改为单一 `Snap` Target（截图拼接架构），已移除广播扩展与 App Group。
- 2026-08-29 已完成：Debug 真机构建、签名校验、安装和启动均成功；iPhone 上的 `com.tao.Snap` 正在运行（版本 1.0，build 1）。
- 2026-08-29 已完成：Release 归档与开发 IPA 已生成，见 `Artifacts/local-development/`。该 IPA 使用开发签名，仅限已注册的开发设备。
- 本次首次构建曾因磁盘空间不足失败；释放空间后已完成全部构建、安装和打包验证。

## 环境基线（2026-08-29）

下表记录本次实际构建与部署所用环境，供复现时比对。不会记录 Apple ID、Team ID、证书指纹、UDID、序列号或网络地址。

| 分类 | 实际环境 | 用途 / 说明 |
| --- | --- | --- |
| 主机系统 | macOS 27.0（Build 26A5416b），Apple Silicon `arm64` | 本机构建与设备部署 |
| Shell | `/bin/zsh` 5.9 | 执行本文命令 |
| 部署工具链 | Xcode 27.0 Beta（Build 27A5228h） | 通过 `DEVELOPER_DIR` 指向；当前设备为 iOS 27，需要匹配的 SDK |
| iOS SDK | iPhoneOS 27.0（Build 24A5390e） | 来自 Xcode 27 Beta |
| Swift 工具链 | Apple Swift 6.4（`swiftlang-6.4.0.27.1`） | 工程仍按 `SWIFT_VERSION = 5.0` 构建 |
| 设备命令行工具 | `devicectl` 642.4 | 列出设备、安装、启动和核验进程 |
| 工程生成器 | XcodeGen 2.45.4 | `project.yml` 修改后用于重新生成工程 |
| 默认 Xcode | Xcode 26.6（Build 17F113） | 已安装但未用于本次部署；其 iOS 26.5 工具链不匹配当前 iOS 27.0 真机 |
| 实体设备 | iPhone 16 Pro，iOS 27.0 | 有线连接、已配对、已启用 Developer Mode |
| 项目配置 | 最低 iOS 17.0；Scheme `Snap`；Debug 真机构建 + Release 归档 | 单一 App Target，自动签名 |

除 Xcode/XcodeGen 外，本文还使用 macOS 自带的 `codesign`、`plutil`、`shasum` 和 `unzip` 分别进行签名、plist、哈希和 IPA 内容校验。

## 前置条件

1. 在 **Xcode → Settings → Apple Accounts** 登录用于开发的 Apple ID，并确认能看到对应的 Team。
2. 在 iPhone 中打开 **设置 → 隐私与安全性 → 开发者模式**，重启后确认开启。
3. 用 USB 连接并解锁 iPhone，选择“信任此电脑”。无线调试也可以，但首次部署建议 USB。
4. 使用 Xcode 27 Beta。当前设备为 iOS 27.0，本机默认 Xcode 26.6 的 iOS 26.5 工具链不能作为本次部署工具链。
5. 确保系统盘至少有 15 GB 可用空间。Xcode 的模块缓存、DerivedData、归档及 IPA 导出都会占用空间。

设置工具链并检查设备：

```zsh
cd /path/to/Snap
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"   # 或你的 Xcode beta 路径

# 工程由 project.yml 生成，Team ID 从环境变量读取，不写进仓库。
export SNAP_DEVELOPMENT_TEAM=XXXXXXXXXX
xcodegen generate

xcodebuild -version
xcrun devicectl list devices
```

从最后一条命令中复制 iPhone 的 `Identifier`，并在当前 shell 中保存（不要将设备 ID 写入仓库）：

```zsh
export DEVICE_ID='从 devicectl 输出复制的 iPhone Identifier'
```

## 首次签名配置

工程只有一个 Target：`Snap`。它不再包含广播扩展，也不再需要 App Group——
截图拼接方案只依赖相册读写权限。

1. 用 Xcode 27 Beta 打开 `Snap.xcodeproj`。
2. 选择 `Snap` Target，打开 **Signing & Capabilities**。
3. 勾选 **Automatically manage signing**，在 **Team** 中选择已登录的 Team。
4. 等待状态显示 **Xcode Managed Profile** 与有效的 **Apple Development** 证书。
5. 如果显示 `No Account for Team` 或 `No profiles`，在 **Xcode → Settings → Apple Accounts** 检查账号，然后回到 Target 重新选择 Team。首次成功时 Xcode 可能会注册设备并创建/刷新 Profile。

首次运行时 iOS 会请求相册权限（`NSPhotoLibraryUsageDescription`）。必须选择「完全访问」或
至少「选择部分照片」，否则 App 无法找到可拼接的截图。

不要把 Apple ID、Team ID、Provisioning Profile、证书或完整设备 ID 写入文档、源码或提交记录。

> 项目由根目录的 `project.yml` 描述。仅当修改该文件或需要重新生成 `.xcodeproj` 时，才运行 `xcodegen generate`；重新生成后应重新检查 Target 的签名设置。

## 真机 Debug 构建与安装

以下命令会生成适合直接安装到当前 iPhone 的 `.app`，不产生 IPA：

```zsh
cd /path/to/Snap
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export DEVICE_ID='从 devicectl 输出复制的 iPhone Identifier'
export DERIVED_DATA="/tmp/Snap-device-deriveddata"

xcodebuild \
  -project Snap.xcodeproj \
  -scheme Snap \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build

export APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/Snap.app"
test -d "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
xcrun devicectl device process launch --device "$DEVICE_ID" com.tao.Snap
```

`devicectl` 重新安装相同 Bundle ID 的开发 App 时会覆盖旧版本；通常会保留应用沙盒数据，但这不是备份机制。若要保留重要数据，请先自行导出。安装成功后可用下列命令核验：

```zsh
xcrun devicectl device info apps --device "$DEVICE_ID" | rg 'com\\.tao\\.Snap|Snap'
```

## Release 归档与 IPA 打包

开发 IPA 仍使用 Apple Development 签名，只适用于已注册的开发设备；它不能用于 App Store、TestFlight 或随意分发。若要公开发布，应使用对应的 Distribution 签名与 App Store Connect 流程。

```zsh
cd /path/to/Snap
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export OUTPUT_DIR="$PWD/Artifacts/local-development"
export ARCHIVE_PATH="$OUTPUT_DIR/Snap.xcarchive"
export EXPORT_PATH="$OUTPUT_DIR/export"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -project Snap.xcodeproj \
  -scheme Snap \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive
```

创建本机临时导出选项文件 `"$OUTPUT_DIR/ExportOptions.plist"`，内容如下：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>debugging</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
```

随后导出并校验 IPA：

```zsh
plutil -lint "$OUTPUT_DIR/ExportOptions.plist"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$OUTPUT_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates

codesign --verify --deep --strict --verbose=2 \
  "$ARCHIVE_PATH/Products/Applications/Snap.app"
shasum -a 256 "$EXPORT_PATH/Snap.ipa"
```

直接调试应优先使用上一节的 `.app` 与 `devicectl`。不要把本机开发签名的 `.ipa`、`.xcarchive`、导出 Profile 或 DerivedData 提交到版本库。

本次已生成的本地开发产物：

- `Artifacts/local-development/Snap.xcarchive`（4.1 MB）
- `Artifacts/local-development/export/Snap.ipa`（100 KB）
- IPA SHA-256：`a64b5b66ca7ee0b2e4a31bcfdd726915eaec94d39696133fc8b4d5ea7d5dfa2f`

## 常见问题

- **设备不出现在 `xcodebuild -showdestinations`**：确认手机已解锁、信任电脑、开启开发者模式，并确保 `DEVELOPER_DIR` 指向 Xcode 27 Beta。
- **`No Account for Team` / `No profiles`**：在 Xcode 账户页登录或刷新 Apple ID，然后回到 `Snap` Target 重新选择 Team。
- **App 里看不到任何截图分组**：确认已授予相册权限，且相册里确实有「连续拍摄、尺寸相同、两张以上」的截图；单张截图不会成组。
- **`No space left on device`**：先释放系统盘至少 15 GB，再重新执行构建。优先检查旧的 DerivedData 和不用的模拟器；清理前确认其中没有其他项目或模拟器需要保留的数据。
- **免费 Personal Team 的 App 数量或过期限制**：删除一台设备上不再需要的开发 App，或重新执行本流程重新签名安装。删除 Snap 会清空其本地数据。
