# GPT 对照功能实现与验证

基线是 `gpt-reference/STATIC_ANALYSIS.md`（2026-11-01 的静态分析快照）。后续实现状态以根目录
`TODOLIST` 为准；基线报告的源码行号不代表修改后的实现位置。没有复制或运行 GPT 的二进制。

## 使用入口

设置页右上角 **参数与工具**，或备份页的 **导入/导出**，打开同一个工具页。

- 定位、地址、时区、音量、OpenUDID、推送 token、安全区、GPU 能力和应用 version/build 可编辑。
- 环境、代理、SDK 兼容和跟踪状态分别启用。兼容选项默认关闭；选择目标应用并重启后检查效果。
- 机型、系统、运营商使用多选列表；版本权重单独编辑，清空权重对象即恢复普通随机。
- 档案支持前后/首末切换、按小时禁用、排序、批量删除、ZIP 导入导出。
- 导出设备参数为 JSON；导入会校验完整参数。导入备份分配新 ID，不自动激活、不覆盖已有档案。
- 清理页提供剪贴板、Safari、选中非系统应用的外部缓存与偏好清理。相册清理通过 Photos 授权流程，
  只删除用户允许访问的项目；不直接修改 Photos.sqlite。

应用版本采用选中进程内 `NSBundle` / `CFBundleGetValueForInfoDictionaryKey` 的读取覆盖，
恢复即移除覆盖。不会改写 `.app/Info.plist`，系统安装列表中的版本保持真实值。
推送 token 和 ATT 状态是应用读值的模拟，不创建 APNs 有效凭据，也不改变系统授权。

## 参数与随机选项

`PhoneInfo` 保留原字段，新增可选的 `runtime`。删除某个覆盖字段表示使用原 API。
例如“高级设备参数”中可保存以下对象：

```json
{
  "location": {
    "latitude": 31.2304,
    "longitude": 121.4737,
    "name": "上海",
    "locality": "上海市",
    "country": "中国",
    "ISOcountryCode": "CN",
    "horizontalAccuracy": 5,
    "verticalAccuracy": 5
  },
  "timeZoneName": "Asia/Shanghai",
  "outputVolume": 0.5,
  "maskEnvironment": false,
  "maskProxy": false,
  "sdkCompatibility": false,
  "hideSimulatedLocation": false,
  "trackingOverride": false,
  "trackingStatus": 3
}
```

其他可选字段：`openUDID`、`pushTokenHex`（偶数长度十六进制）、`screenTopInset`、
`screenBottomInset`、`gpuWorkingSetSize`（字节）、`gpuRaytracing`（0/1）、
`interfaceOrientation`、`timeSinceLastLaunch`、`appVersions`。

`appVersions` 示例：`{"com.example.demo":{"version":"1.2.3","build":"42"}}`。
位置字典还支持 altitude、speed、course、街道、区、行政区和邮编。
时区名称必须能被 NSTimeZone 识别；数值范围、嵌套类型和 UUID 会在保存、导入时校验。

“随机策略与清理选项”保存完整设置对象。`options` 支持：

| 字段 | 含义 |
|---|---|
| models / versions / carriers | 机型标识、系统版本、运营商名称的多选数组；空数组不限制 |
| versionWeights | 版本到非负权重的对象；必须有正权重；省略表示不加权 |
| wifiPercent / fiveGPercent | WiFi 占比，以及蜂窝中 5G 占比，均为 0–100 |
| useLocalModelOS | 使用当前设备的机型和系统；包内无数据时明确报错 |
| requireRealRAM | 只选有 KMDevSpecial 机型+OS 特例的组合 |
| runtimeTemplate | 每次新机使用的 runtime 模板 |
| preservedPaths | 保留的沙盒相对路径，例如 Library/Preferences/token.plist |
| clearRelatedContainers | 备份/恢复 AppGroup 和扩展容器；默认关闭 |
| clearPasteboardOnNewPhone / clearPasteboardOnSwitch | 对应操作成功后清剪贴板 |
| stopAtLastProfile | 到首末边界停止；关闭后循环，并跳过禁用档案 |
| backupKeychain | 启用下述本地密码项代理；默认关闭 |
| idfaEndpoint | 用户自己配置的 HTTPS IDFA 服务；留空只本地随机 |
| fallbackRandomIDFA | 外部服务失败时是否使用本地随机；默认关闭 |

外部服务接受纯文本 UUID 或 `{"idfa":"UUID"}`。没有使用 GPT 包中的网址、访问密钥或激活服务，
也未验证任何外部 IDFA 的“真实性”。请求失败且未允许回退时，在清理前报错。

RAM 保留名义 GiB，同时增加 `physicalMemoryBytes`，从 KMDevSpecial 获取真实字节值；
NSProcessInfo、sysctlbyname、host_info 和内存统计共用字节值，网页的 deviceMemory 保留名义 GiB。

## 备份、恢复与文件边界

新机先生成、校验参数，再创建未激活档案、备份原状态；目标参数和备份校验后才清理/恢复。
切换失败会尝试恢复原档案与参数；回滚失败会报告保留备份的位置。
批量删除先暂存目录，原子保存档案索引，再清理暂存目录；当前档案与 ID 0 保留。

保留规则仅允许 Documents、Library、tmp、SystemData 下的相对路径。
导入拒绝绝对路径、`..`、符号链接、硬链接、特殊文件与重复路径。
归档最多 100000 项、展开数据最多 8 GiB；超限报错并删除导入暂存目录。
v1 ZIP 格式含 `manifest.json` 和 `profiles/<原ID>/`，每个档案必须有合法的 `phoneInfo.json`。
此格式不是 GPT ZIP 格式的直接兼容承诺。

传输目录：`/private/var/mobile/Media/ProjectX/Transfer/Exports` 与 `Imports`。
相关容器从 LaunchServices 元数据解析，保留容器管理元数据；不按模糊包名扫描或删除全部共享容器。

## 钥匙串代理的范围

注入目标 App 的 KeychainAgent 使用该 App 自身的 access groups，通过 Security API 备份
本地 generic/internet password。不会全局 SQL 删除系统 genp/cert/keys/inet 表。

启用 backupKeychain 后，备份时目标 App 必须已运行并加载插件；5 秒内不响应或项目受保护不可导出时，
在清理前失败。恢复在目标 App 下次启动时处理 Pending 请求；可在“钥匙串恢复状态”查看确认结果。
恢复前保存原密码项，失败尝试回滚。IPC 临时文件不进入普通沙盒快照，钥匙串文件权限为 0600。

证书、私钥、Secure Enclave、iCloud 同步项目及设备间迁移尚未实现，F28 保持未完成。
本地密码代理也需要真机验证，不能把档案切换成功当成钥匙串恢复已确认。

## SDK 与检测处理的边界

`hooks/PXSDKTargets.h` 纳入基线里的 60 个 SDK 类、94 个方法目标，另有 UIDevice 自定义检测入口。
加载动态库时重试发现，核对方法参数数量和类型后安装；没有对应类的方法不会创建伪类。

105 个目标均有显式行为适配器，覆盖整数/布尔检测、AIMeta NSNumber、MP cydia、GT3 py/jdb/deb、
FFM NETS/RDATES、IDFV、AppsFlyer p/lr 字符串方向/浮点时间、位置验证及可选采集/归因处理。
SDK 采集、初始化、Realm 写入抑制、归因 token 抑制、元数据改写分别使用
`sdkSuppressCollectors`、`sdkSuppressInitialization`、`sdkBlockRealmWrites`、`sdkSuppressAttribution`、
`sdkRewriteMetadata`；工具页均有独立开关，默认关闭，且须同时开启 SDK 兼容。
AES、Realm 创建等 GPT 仅记录日志的入口保留原调用一次；不写明文/密钥日志。
签名不匹配会记录 `signature-mismatch`，保留原方法。F15 的基线代码和本地验证已完成；
F14 的首次自动 +load 已改为初始化分发前同步安装；原生 Hook 真实 dylib 测试中，
五个目标开启时原初始化为 0 次、关闭时为 1 次。已完成的初始化不会重放或撤销；
未知运行时入口形式降级并保留原行为。没有证明所有 App/SDK 版本真机可用。
逐方法的适配分支、透传行为与剩余工作记录在 [SDK_COMPATIBILITY.md](SDK_COMPATIBILITY.md)。
不会照搬 GPT 的 Memora 固定偏移；没有安装路径证据的 MGCopyAnswer 等导出替换函数也未当作完成项。

环境层已覆盖一组文件、URL、环境变量、镜像名与代理/接口查询入口；bind/connect、异常端口、
mach_vm_region、运行时符号隐藏等其余入口仍留在 F12。F29 的系统数据库/iCloud 深度清理也未完成。

## 自动化

后台只监听 `127.0.0.1:8888`，仍未实现鉴权。普通读接口继续兼容，新增统一命令接口：

```json
{"command":"navigateProfile","parameters":{"operation":"next"}}
```

向 `POST /command` 发送上述 JSON。支持 getSettings/saveSettings/getCatalog/listProfiles、
newPhone/switchProfile/navigateProfile、renameProfile/disableProfile/reorderProfile/deleteProfiles、
exportProfiles/importProfiles、exportParameters/importParameters、setPhoneInfo/modifyIdentifier/randomIDFA、
setAppVersion/updateParameters、clearPasteboard/clearSafari/clearSystemResidues、keychainStatus/fetchIDFA。
import 命令仅接受 Imports 目录中的 `filename`，不接受任意系统路径。
成功返回 `{"status":"success","data":...}`，失败返回 HTTP 400 与 message；长操作不使用普通读请求的 10 秒超时。

URL 示例（名称参数需要 URL 编码）：

```text
projectx://cmd/newPhone
projectx://cmd/newPhone?version=18.5&model=iPhone14%2C7
projectx://cmd/nextBackupData
projectx://cmd/preBackupData
projectx://cmd/activeFirstBackupData
projectx://cmd/activeLastBackupData
projectx://cmd/activeBackupDataByName?name=demo
projectx://cmd/setDisableTime?name=demo&time=2
projectx://cmd/exportPara
projectx://cmd/setAppVersion?bundleID=com.example.demo&version=1.2&build=42
```

保留 weaponx scheme；未注册 GPT scheme，避免抢占 GPT 原应用。
执行结果写到 `/private/var/mobile/Media/ProjectX/command-result.json`。

## 验证

独立 Foundation 回归使用临时目录和 127.0.0.1 HTTP fixture，覆盖配置、内存单位、URL 解析、
ZIP 往返和恶意归档拒绝、目录保留、档案禁用/顺序/导入、索引失败回滚及原 HTTP 测试。
本地原生 Hook 回归共 918 项通过（SDK 341、签名拒绝 170、ABI/入口解析 95、动态库加载 103、功能 86、原有 123）。
未配置本机 Hook 库的默认回归为 849 项。原生 Hook 库仅用于 macOS 测试，不进入 iOS 安装包。
SDK 模拟类验证了 105 个目标安装、原调用保留、继承/异常回退与并发。Theos 三种模式分别 clean、编译打包；
安装包路径、SHA256 与 Mach-O 检查记录在 [BUILD_VERIFICATION.json](BUILD_VERIFICATION.json)。
真实注入、AppGroup 权限、SDK 动态加载、照片授权与钥匙串往返仍需设备验证。
