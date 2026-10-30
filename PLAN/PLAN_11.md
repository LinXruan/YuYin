# PLAN_11：Release 构建、独立签名与 com.release.yuyin 包名（112）

## 背景

PLAN_10 已完成 112 版本并交付 debug APK。当前工程存在两个问题：

1. 只验证过 `flutter build apk --debug`，尚未验证 release 构建；
2. `android/app/build.gradle.kts` 中 release 构建类型仍复用 **debug 签名**，且 debug / release 的 `applicationId` 相同（`com.debug.yuyin`），两种包无法同时安装在真机上。

本次目标：

- 尝试并跑通 **release APK** 构建；
- release 使用**单独的私钥**签名（不复用 debug keystore）；
- release 包名改为 **`com.release.yuyin`**，debug 保持 `com.debug.yuyin`，两者可共存；
- 在 `CLAUDE.md`（以及 README）补充 release 包名与签名说明。

版本保持 **`1.0.0+112`**（本次不涉及功能改动，也不要求升版本号）。

## 实现方案

### 1. 生成独立的 release 私钥

- 使用 JDK 17 的 `keytool` 生成 **JKS** keystore：
  - 路径：`android/app/yuyin-release.jks`
  - 别名：`yuyin-release`
  - 算法：RSA 2048，有效期 10000 天
  - storePassword / keyPassword 使用随机生成的强密码
- 密码写入 `android/key.properties`（已被 `android/.gitignore` 忽略）：

  ```properties
  storePassword=...
  keyPassword=...
  keyAlias=yuyin-release
  storeFile=yuyin-release.jks
  ```
- `yuyin-release.jks` 与 `key.properties` **均不提交到 Git**（现有 `android/.gitignore` 已覆盖 `key.properties`、`**/*.jks`）。
- 提醒用户自行备份这两个文件；私钥丢失后无法再对同一包名发布覆盖安装的更新。

### 2. Gradle 配置（`android/app/build.gradle.kts`）

- 在文件顶部读取 `rootProject.file("key.properties")`（`android/key.properties`）；
- 新增 `signingConfigs.release`，从 key.properties 读取别名、密码与 keystore 路径；
- `buildTypes.release` 改为使用 `signingConfigs.release`，不再使用 debug 签名；
- 通过 AGP Variant API 给 release 变体单独指定包名：

  ```kotlin
  androidComponents {
      onVariants(selector().withBuildType("release")) { variant ->
          variant.applicationId.set("com.release.yuyin")
      }
  }
  ```

- debug 变体不受影响：`applicationId` 仍为 `com.debug.yuyin`，仍使用 debug 签名；
- `namespace` 与 `MainActivity` 包名保持 `com.debug.yuyin` 不变（namespace 是代码/资源命名空间，不决定安装后的包名；安装包名由 applicationId 决定）。

> 已确认当前工程使用的 AGP 9.1.0 中 `ApplicationVariant.applicationId` 可写，可直接用上述 Variant API。
> 若实际构建发现该 API 与 Flutter 工具链冲突，备选方案：改用 product flavor（`--flavor`）为 release/debug 分别设置 applicationId，并在本文档记录变更。

### 3. 文档更新

- `CLAUDE.md`：
  - 项目概况：包名写明 debug `com.debug.yuyin` / release `com.release.yuyin`；
  - 常用命令：新增 `flutter build apk --release` 及产物路径；
  - 环境要点：新增 release 签名说明（`android/key.properties` + `android/app/yuyin-release.jks`，不提交、需备份）；
  - 包名同步说明：说明 release 包名由 build.gradle.kts 的 Variant API 控制，namespace / MainActivity 不变。
- `README.md`：同步包名与 release 构建命令（不写入任何密码）。

### 4. 验证流程

1. `flutter analyze`：无问题；
2. `flutter test`：全部通过；
3. `flutter build apk --release`：构建成功；
4. `aapt dump badging` 校验 release APK：
   - `package=com.release.yuyin`
   - `versionCode=112` / `versionName=1.0.0`
   - `application-label=余音`
5. `apksigner verify --print-certs` 校验：
   - release APK 的证书为本次生成的 `CN=LinXruan, OU=YuYin...`，**不是** Android Debug；
   - 与 `app-debug.apk` 的 debug 证书指纹不同；
   - APK Signature Scheme v2 验证通过（minSdk 24 下默认不启用 v1/v3，可正常安装）。
6. 重新执行 `flutter build apk --debug`，确认 debug APK 仍为：
   - `package=com.debug.yuyin`
   - 使用 debug 签名。
7. 不主动安装到真机；APK 交付后由用户真机测试（release 与 debug 可共存）。

## 涉及文件

### 修改

- `android/app/build.gradle.kts`：release 签名配置 + release applicationId
- `CLAUDE.md`：release 包名 / 签名 / 构建命令说明
- `README.md`：包名与构建命令同步

### 新增（本地，不提交）

- `android/key.properties`
- `android/app/yuyin-release.jks`

### 产物

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/flutter-apk/app-debug.apk`（用于对照验证）

## 风险与备注

- 私钥与密码仅保存在本机，**必须备份**；丢失后无法覆盖更新 `com.release.yuyin`。
- release APK 与 debug APK 包名不同，可同时安装；两者数据相互独立。
- 若改包名后桌面出现两个"余音"图标，属于预期现象。
- 本次不修改 Dart 代码，`app_info.dart` 中的版本号保持 `1.0.0+112`。

## 执行结果

### 1. 私钥与签名

- 已生成 `android/app/yuyin-release.jks`（JKS，别名 `yuyin-release`，RSA 2048，有效期 10000 天）；
- 已生成 `android/key.properties`（随机强密码，未打印到日志/文档）；
- `git check-ignore` 确认两个文件均被 `android/.gitignore` 忽略，不会进入版本库。

### 2. Gradle

- `android/app/build.gradle.kts` 已加入 key.properties 读取、`signingConfigs.release`、release 签名绑定；
- `androidComponents.onVariants(selector().withBuildType("release"))` 成功将 release 包名设为 `com.release.yuyin`，无需启用备选 flavor 方案；
- `namespace` 与 `MainActivity` 保持 `com.debug.yuyin`。

### 3. 文档

- `CLAUDE.md` 已补充 debug / release 双包名、release 构建命令、签名文件说明，并新增第 6 节「包名与 Release 构建」；
- `README.md` 已同步包名、构建命令与 APK 输出路径。

### 4. 验证

- `flutter analyze`：No issues found
- `flutter test`：35 个测试全部通过
- `flutter build apk --release`：成功，`app-release.apk`（50.7MB），Gradle 耗时 144.3s
- `aapt dump badging`（release）：
  - package=`com.release.yuyin`
  - versionCode=`112` / versionName=`1.0.0`
  - application-label=`余音`
  - launchable-activity=`com.debug.yuyin.MainActivity`（namespace 未变，属预期）
- `apksigner verify`（release）：
  - 证书 DN：`CN=LinXruan, OU=YuYin, O=YuYin, L=Unknown, ST=Unknown, C=CN`
  - 证书 SHA-256：`fcdabd0b7edc0196f6713f121159214147623cbb59dda83b5210e5503ba1f093`
  - 使用 APK Signature Scheme v2（minSdk 24 下 apksigner 默认不启用 v1/v3，可正常安装）
- `flutter build apk --debug`：成功（8.1s）
- debug APK 对照：
  - package=`com.debug.yuyin`
  - 证书 DN：`C=US, O=Android, CN=Android Debug`
  - 证书 SHA-256：`36082573740be529607834cba50932b449ae72ae070a2f504dfe3c0bb69f35a5`
  - 与 release 证书不同，确认 release 未复用 debug 私钥

### 5. 产物

- release：`build/app/outputs/flutter-apk/app-release.apk`
- debug：`build/app/outputs/flutter-apk/app-debug.apk`

未自动安装到真机，等待用户真机测试。修改尚未提交 Git（用户未要求提交）。
