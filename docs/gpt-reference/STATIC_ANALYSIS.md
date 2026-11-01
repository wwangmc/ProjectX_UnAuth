# GPT 2.14-602 与 ProjectX_UnAuth 静态对比清单

分析对象为当前目录中的 deb 和 ProjectX_UnAuth 工作副本。此处的 GPT 是该 iOS 插件包的名称。已解包、读取 Mach-O 和源码；未安装插件、执行安装脚本、连接其服务器或修改 ProjectX。

**结论：ProjectX 已有常见设备参数伪装和基本档案管理；主要缺口在定位/地址、越狱与 VPN/代理检测处理、SDK 专用入口，以及参数策略和备份工作流。** 以下 29 项按功能分组，最后两项明确保留接入不确定性。不能把“同名 Hook 缺失”直接等同为“整项功能缺失”。

## 1. 范围与证据口径

- deb：`com.ghb.ios.gptuk_2.14-602_iphoneos-arm64.deb`，包名 `com.ghb.ios.gptuk`，版本 `2.14-602`。
- SHA-256：`b1f90a8683447a26e95dcbaa265c31464f4ad0846153113a646735448ee4f12d`。
- 包内：GPT.app/GPT（arm64）、gpttweak.dylib（arm64）、gptdaemon（arm64/arm64e）、DeviceInfo.db、配置资源。tweak/app 的 `cryptid=0`。后台为 root 的 MachService `com.km.gptdaemon`，应用通过 NSXPCConnection 调用。
- GPT 注入 plist 过滤 `com.apple.CoreFoundation`；实际行为还由进程排除、`openStatus`、`appids` 和各功能开关控制。
- ProjectX 的生效代码范围依据 [Makefile](../../Makefile:34)。`ProjectXTweak/` 不在根构建中，其 AppContainerHooks/AppGroupHooks/AppInstallHooks/AppVersionHooks/CoreDataHooks/KeychainHooks/VPNDetectionBypass **7 个 .x 均为 0 字节**。
- GPT 查到 **235 处 Substrate 注册调用点：203 处 MSHookMessageEx、32 处 MSHookFunction**；另有 **19 项 fishhook 表项**。这些是代码位置/表项数，包含替代路径、重复目标、动态类和专用条件，不能说成“254 个已生效 Hook”。
- 地址为未滑移 Mach-O 虚拟地址；app 地址带 `0x100...`，tweak 地址从 `0x...` 起。没有真机运行验证。源码“有实现”也不保证在特定系统成功生效。
- 已解析 dyld chained fixups、CFString、ObjC selector/stub、注册参数，避免只凭 strings 或依赖库判断功能。原始证据、自动提取脚本、审阅后的差异表均保留。

## 2. ProjectX 缺少或覆盖不足的功能

| 编号 | 判定 | 功能 | GPT 证据 | ProjectX 现状 |
|---|---|---|---|---|
| F01 | 缺少 | **定位回调坐标替换** | CLLocationManager setDelegate:；动态代理 locationManager:didUpdateLocations:；使用 newLat/newLng 重建 CLLocation；`注册 0x1160ec、0x1172e4；实现 0x113ab8` | 当前 hooks 无 CLLocationManager/CLLocation Hook；PhoneInfo 无经纬度字段。[model/PhoneInfo.h](../../model/PhoneInfo.h:6) |
| F02 | 缺少 | **地址与逆地理编码一致性** | CLPlacemark 的 location/name/街道/城市/国家/ISOcountryCode 等；CLGeocoder reverseGeocodeLocation:completionHandler:；`注册 0x116118–0x116284；实现 0x117310–0x117c1c` | 当前 hooks 无 CLPlacemark、CLGeocoder。[hooks/Tweak.x](../../hooks/Tweak.x:336) |
| F03 | 缺少 | **模拟定位来源标志处理** | CLLocationSourceInformation isSimulatedBySoftware / isProducedByAccessory；`注册 0x1162b0、0x1162d0；实现返回 0` | 当前无对应类 Hook。[model/PhoneInfo.h](../../model/PhoneInfo.h:6) |
| F04 | 缺少 | **时区伪装** | __NSLocalTimeZoneI、__NSTimeZone 的 name / secondsFromGMT；newTimezoneName；`注册 0x11694c–0x1169b4；实现 0x119574–0x1197b8` | 无时区字段或 NSTimeZone Hook。[model/PhoneInfo.h](../../model/PhoneInfo.h:6) |
| F05 | 缺少 | **系统输出音量值伪装** | AVAudioSession outputVolume / getOutputVolume；newVoiceL；`注册 0x116904、0x116924；实现 0x119484、0x1194fc` | 无 AVAudioSession 音量 Hook 和对应参数。[model/PhoneInfo.h](../../model/PhoneInfo.h:6) |
| F06 | 缺少直接入口 | **OpenUDID、广告跟踪状态及 ATT 回调** | OpenUDID +value；ASIdentifierManager isAdvertisingTrackingEnabled；ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:；`0x1160c4、0x11606c、0x116098；实现 0x11714c/0x1171a4` | 已有 IDFA/IDFV；未覆盖上述 3 个入口。ATT Hook 返回的授权状态不等同系统真实授权改变。[hooks/Tweak.x](../../hooks/Tweak.x:95) |
| F07 | 缺少 | **交给 App 的推送 token 替换** | 动态 AppDelegate application:didRegisterForRemoteNotificationsWithDeviceToken:；读取 newPushTokenData；`注册 0x1209b4；实现 0x120778` | 无推送 token 参数及回调 Hook；不表示能生成 APNs 有效 token。[model/PhoneInfo.h](../../model/PhoneInfo.h:6) |
| F08 | 部分覆盖 | **屏幕入口与安全区一致性** | UIScreen nativeScale；UIScreenMode size；UIWindow safeAreaInsets；`0x116a40、0x116a90、0x116a68` | 已有 bounds/nativeBounds/scale；native_scale 拼写不等于 nativeScale；无另外两项。[hooks/DeviceSpecHooks.x](../../hooks/DeviceSpecHooks.x:167) |
| F09 | 部分覆盖 | **主机名与 CPU 底层入口** | NSProcessInfo hostName / activeProcessorCount；C host_info；`0x116858、0x1168b8、0x116e14` | 已有 NSHost name、processorCount、sysctl、host_statistics64；无这 3 个相同入口。[hooks/DeviceSpecHooks.x](../../hooks/DeviceSpecHooks.x:275) |
| F10 | 部分覆盖 | **Network.framework 的 C API 路径** | nw_path_uses_interface_type、nw_path_has_ipv4/ipv6、nw_interface_get_type/name；`0x116ea0–0x116f10` | ProjectX 主要覆盖 NWPath ObjC、Reachability、getifaddrs；未 Hook 这 5 个 C 入口。[hooks/NetworkConnectionTypeHooks.x](../../hooks/NetworkConnectionTypeHooks.x:506) |
| F11 | 部分覆盖 | **Metal 实际设备类与 GPU 能力** | MTLCreateSystemDefaultDevice 返回对象的类：name / recommendedMaxWorkingSetSize / supportsRaytracing；`0x11bcb8、0x11b904、0x11b924、0x11b944` | 仅 %hook MTLDevice 的 name/familyName；缺少构建设备函数和后两项，且协议名是否能命中运行时类需实测。[hooks/DeviceSpecHooks.x](../../hooks/DeviceSpecHooks.x:431) |
| F12 | 缺少 | **通用越狱痕迹与调试检测处理** | 文件探测、URL scheme、环境变量、镜像名、符号查找、socket、异常端口、虚拟内存区等；`loadJBHooks 0x11bb80；19 项 fishhook 表 0x2e4d90；ObjC 构造器 0x11c290` | 活动源码无成套实现；VPNDetectionBypass.x 是 0 字节历史文件。[Makefile](../../Makefile:34) |
| F13 | 部分覆盖 | **VPN/代理检测结果处理** | CFNetworkCopySystemProxySettings；getifaddrs 中过滤接口；DeviceInfo / SpectrumReachability / AppsFlyerUtils / ALUtils / MTGDeviceHandler 等；`0x11bc9c、0x11ad4c、0x115fe0、0x116adc、0x11c3b0、0x122240` | 有网络类型/IP 伪装；没有对应代理字典清理和专门检测类 Hook；HttpRequest 自身的代理配置不算给目标 App 的 Hook。[hooks/NetworkConnectionTypeHooks.x](../../hooks/NetworkConnectionTypeHooks.x:433) |
| F14 | 缺少直接入口 | **第三方 SDK 越狱/调试/沙盒检测适配** | AppsFlyerUtils、JailMonkey、SecurityWarnings、OneSignal、UMUtils、PAGDeviceHelper、PayPal 相关类等；`详见 Hook 全量清单及 SDK 附表` | 当前 hooks 无这些目标类；通用 API 修改不能直接证明覆盖这些 SDK 自有检测。[Makefile](../../Makefile:34) |
| F15 | 缺少直接入口 | **SDK 标识、归因与设备参数专用修改** | SensesDevice、LSApplicationProxy deviceIdentifierForVendor、AFSDKDevice、AFSDKiAdClient、AppsFlyerAES128Crypto、ATURLArgumentModule、ALDataCollector、MTGDeviceInfo；`0x116548、0x116590、0x116bb4/0x116bdc、0x1221e8、0x122214、0x122268` | ProjectX 有系统 IDFA/IDFV 和网络参数；无这些专用入口；各 SDK 版本兼容性未验证。[hooks/Tweak.x](../../hooks/Tweak.x:112) |
| F16 | 缺少/占位 | **应用 version/build 修改和恢复** | GPTAppVersionVC 修改 Info.plist 的 CFBundleShortVersionString / CFBundleVersion，并保存 *_b 原值；也有 URL 命令；`App 0x1000d534c；URL 处理 0x1000d1a6c` | AppVersionHooks.x 0 字节且不参与构建；当前 App 没有相同编辑流程。GPT 这里是文件修改，不是已证实的 NSBundle 版本 Hook。[Makefile](../../Makefile:34) |
| F17 | 缺少 | **App Group 与扩展容器清理** | toCleanAppData 遍历 plugInKitPlugins、Shared/AppGroup、容器元数据；还有 AppDataCleaner 专用清理实现；`App +[KMPublicFunc toCleanAppData] 0x1000f0334` | ActionManager 主要处理主 dataContainer 的 Documents/tmp/Library/SystemData；无 AppGroup/PluginKit 关联清理。[daemon/ActionManager.m](../../daemon/ActionManager.m:154) |
| F18 | 缺少 | **按文件/子目录选择保留的过滤规则** | KMDirInfoDetailVC/KMDirInfoMod filtType；KMFliteFile.plist；toCleanOneItem:fites: 递归过滤；`App 0x1000e9fc0、0x1000efbd0、0x1000effb8` | 仅 App 级范围；备份/恢复按固定 4 目录操作，无文件树保留清单。[daemon/ActionManager.m](../../daemon/ActionManager.m:154) |
| F19 | 占位 | **备份 ZIP 导入导出** | 备份批量导出；设置页 ZIP 打包/解包路径，SSZipArchive 调用；`App 0x1000cfd5c、0x1000f6854、0x1000f6a8c` | 导入/导出按钮仅弹 later 提示，未实现打包导入流程。[ProfileTabViewController.m](../../ProfileTabViewController.m:1333) |
| F20 | 缺少 | **新机参数文件的独立导入导出** | exportPara / importPara；gptexportpara、gptimportpara；保留 backupId；`App +[KMPublicFunc exportPara] 0x1000f2a74；importPara 0x1000f2c60` | 已有 JSON phoneInfo 保存与 HTTP 读写；无同等独立文件传输工作流。[model/PhoneInfo.h](../../model/PhoneInfo.h:51) |
| F21 | 缺少/部分占位 | **备份禁用时间、顺序切换、首末条及批量操作** | disableTime；doNext:/doPre:；activeFirst/Last；手工排序；批量删除/导出；`App 0x1000c7c3c、0x1000c83e8、0x1000c8710、0x1000c9910、0x1000cf564` | 已有搜索、单条切换/重命名/删除；没有禁用时间、上/下条命令及同等批量流程；deleteAllProfiles 内 TODO clearAll。[ProfileTabViewController.m](../../ProfileTabViewController.m:1380) |
| F22 | 部分覆盖 | **URL scheme 命令集与执行结果文件** | GPT://cmd/newPhone、next/preBackupData、activeFirst/Last、按名切换/删除、modifyIdfa、setAppVersion、exportPara 等；gptresult.txt；`App -[GPTAppDelegate application:openURL:options:] 0x1000d1a6c` | ProjectX 有 HTTP 后台接口；Info.plist 注册 URL scheme，但 SceneDelegate 只读 URL 无命令分发，不能算已支持同等 URL 命令。[ProjectXSceneDelegate.m](../../ProjectXSceneDelegate.m:49) |
| F23 | 部分覆盖 | **可配置随机参数策略** | 机型/OS/运营商/网络多选；OSPercent 权重；WiFi/5G 占比；KEnableRealRamOS；KEnableUseLocalModeOS；`App getNewPhonePara 0x1000fe3e0；getRandomNets 0x100100298；SystemVersionRatioController doSave 0x10010d6e0` | 已有运营商国家和 iOS 最低/最高版本；无同等多选/权重/本机模式设置，使用普通随机 SQL。[common/SettingManager.h](../../common/SettingManager.h:5) |
| F24 | 部分覆盖 | **按机型和 OS 获取 RAM/容量特例** | toGetOneDeviceSpecialInfo:v: 以及 KEnableRealRamOS 筛选；GPU 内存/光追字段；`App 0x1000fe3e0` | ProjectX 包内也有 KMDevSpecial 表，但生成器用 KMDevices.RAM/storage，未查询 KMDevSpecial；不能把数据库表存在算作完成。[daemon/DataGenManager.m](../../daemon/DataGenManager.m:940) |
| F25 | 缺少操作流程 | **主动清剪贴板及新机/切备份时清理** | clearParseboard 处理 pasteboardd 和缓存；newPhoneClearPasteboardStatus / backupClearPasteboardStatus；`App +[KMPublicFunc clearParseboard] 0x1000eba40` | PasteboardHooks 是读写值/标识修改；ActionManager 无对应主动清理及开关。[hooks/PasteboardHooks.x](../../hooks/PasteboardHooks.x:103) |
| F26 | 部分覆盖 | **独立 Safari 清理入口** | cleanSafariData 终止 MobileSafari 后清理其 data container、CloudKit 等；单独按钮；`App 0x1000ebb98、0x1000e1908` | 仅在 newPhone 且 Safari 被选中时额外删除 Library/Safari；无等价独立清理入口。[daemon/ActionManager.m](../../daemon/ActionManager.m:48) |
| F27 | 缺少代码路径；服务未验证 | **从外部服务获取 IDFA 值** | getRealIDFA 读取 GetRealeIDFAURL 发起网络请求，并有失败退回随机值提示；`App 0x1000df2f8` | ProjectX 本地随机 NSUUID；没有此网络获取路径。“真实”是 GPT 文案，未验证服务或返回值真实性。[daemon/DataGenManager.m](../../daemon/DataGenManager.m:31) |
| F28 | 待确认接入 | **按 App 备份钥匙串数据的方法** | backupKeychain:para:；getKeydata:path:；wirteKeyDataToDb:path:；genp/cert/inet/keys；`App 0x1000ee6f0、0x1000e7b20、0x1000e7dfc` | ProjectX 只有系统钥匙串 SQL 删除，不备份恢复；GPT 方法非空，但未确认主备份/恢复调用链，故不列为已证实完整功能。[daemon/ActionManager.m](../../daemon/ActionManager.m:108) |
| F29 | 方法存在；接入待确认 | **相册与更多系统残留清理** | toCleanPhotoData/cleanPhotoDBData；AppDataCleaner 的 URL 凭据、Spotlight、iCloud、receipt、系统 DB 等；`App 0x1000eec84；AppDataCleaner 方法摘要` | ProjectX 无这些专用流程；GPT 多个相似命名方法也是 ret 空实现，需逐项接入确认，不能笼统宣称全覆盖。[daemon/ActionManager.m](../../daemon/ActionManager.m:27) |

## 3. Hook 层面的缺口速查

以下写出入口族；完整逐调用点表见 [GPT_vs_ProjectX_Hook差异.csv](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/GPT_vs_ProjectX_Hook差异.csv)。它同时保留“ProjectX 已有”的行，便于查验差集。

| 入口族 | GPT 有注册/表项的入口 | ProjectX 判定 |
|---|---|---|
| 定位 | `CLLocationManager setDelegate:` → delegate `locationManager:didUpdateLocations:`；`CLPlacemark` 属性；`CLGeocoder reverseGeocodeLocation:completionHandler:`；`CLLocationSourceInformation` 两个来源标志 | 缺少 |
| 跟踪与标识 | `OpenUDID +value`、`ASIdentifierManager isAdvertisingTrackingEnabled`、`ATTrackingManager +requestTrackingAuthorizationWithCompletionHandler:`、`LSApplicationProxy deviceIdentifierForVendor` | 缺少直接入口；IDFA/IDFV 基础功能已有 |
| 音量/时区 | `AVAudioSession outputVolume/getOutputVolume`、`__NSLocalTimeZoneI`/`__NSTimeZone name/secondsFromGMT` | 缺少 |
| 屏幕 | `UIScreen nativeScale`、`UIScreenMode size`、`UIWindow safeAreaInsets` | 部分；`native_scale` 拼写错误 |
| CPU/主机 | `NSProcessInfo hostName/activeProcessorCount`、`host_info` | 部分；processorCount/sysctl/内存其他入口已有 |
| Network C | `nw_path_uses_interface_type`、`nw_path_has_ipv4`、`nw_path_has_ipv6`、`nw_interface_get_type`、`nw_interface_get_name` | 缺少这些 C 入口；NWPath ObjC 部分已有 |
| GPU | `MTLCreateSystemDefaultDevice` → 返回对象类的 `name/recommendedMaxWorkingSetSize/supportsRaytracing` | 部分；仅声明 `%hook MTLDevice name/familyName` |
| 文件/URL 探测 | `fopen`、`access`、`lstat`、`stat`、`__open`、`readlink`；`UIApplication canOpenURL:`；`NSFileManager fileExistsAtPath:/isReadableFileAtPath:/subpathsAtPath:/subpathsOfDirectoryAtPath:error:/attributesOfItemAtPath:error:`；`NSData/NSString writeToFile:atomically:` | 无对应越狱探测处理体系。ProjectX 的版本文件读取 Hook 不等价 |
| 镜像/符号/环境 | `_dyld_get_image_name`、`objc_copyImageNames`、`dlopen`、`dlsym`、`NSClassFromString`、`getenv`、`raise` | 缺少这些处理入口；ProjectX 的 dyld UUID 修改是另一功能 |
| socket/代理/调试 | `bind`、`connect`、`CFNetworkCopySystemProxySettings`、`task_get_exception_ports`、`mach_vm_region`；`getifaddrs` 过滤 | 多数缺少；getifaddrs 已有 IP 修改，语义不同 |
| 生命周期/推送 | `UIApplicationMain`、动态 AppDelegate/SceneDelegate 的生命周期与 URL 回调，特别是远程通知 token 回调 | 缺少同等注入流程；App 自己的生命周期方法不算对目标 App 的 Hook |
| 其他特定入口 | `DCDevice isSupported`、`MFMessageComposeViewController canSendAttachments/canSendSubject/canSendText`、`SBHomeHardwareButtonActions`、`SBMainWorkspace`、`UIView addInteraction:`、`NSURLSession dataTaskWithRequest:completionHandler:`、`NSMutableURLRequest +requestWithURL:` | 无直接对应；部分是 App 专用/日志/抑制行为，不能都算通用伪装功能 |

其中 `lstat/stat` 在 fishhook 表中有证据，但不在 loadJBHooks(true) 的直接 MSHookFunction 分支中。完整清单按机制分别保留。

## 4. SDK 专用 Hook：ProjectX 未找到同目标类入口

表内为二进制中真正传给 MSHookMessageEx 的类和 selector，不是仅出现的字符串。只有目标 App 内存在对应版本的类/方法时才可能生效；名称不作为 SDK 厂商/版本归属的充分证明。`+` 表示类方法，`-` 表示实例方法。

| 目标类 | 注册的方法 |
|---|---|
| `ABKLocationUtilities` | `+isValidLocationAndAccurateEnough:` (0x116b0c); `+locationIsValidWithLatitude:longitude:` (0x116b2c) |
| `AFSDKDevice` | `+identifierForVendor` (0x116bdc) |
| `AFSDKiAdClient` | `-appleAdsAttributionToken` (0x116bb4) |
| `AIMetaDataCollector` | `-getDeviceJailbrokenState` (0x11c4b4) |
| `ALDataCollector` | `-requestParametersWithAdInfo:nested:` (0x122268) |
| `ALISCSecurity` | `+isJailBreak` (0x122354) |
| `ALUtils` | `+isVPNConnected` (0x122240) |
| `ANSMetadata` | `-computeIsJailbroken` (0x11c628); `-isJailbroken` (0x11c644) |
| `ATURLArgumentModule` | `+getTrackCommonParameters` (0x122214) |
| `AppsFlyerAES128Crypto` | `+encrypt:withObject:` (0x1221e8) |
| `AppsFlyerTracker` | `-setSkipAdvancedJailbreakValidation:` (0x11c43c); `-getTimePassedSinceLastLaunch` (0x11c45c) |
| `AppsFlyerUtils` | `+isVPNConnected` (0x11c3b0); `+isJailBreakon` (0x11c3d0); `+isJailbrokenWithSkipAdvancedJailbreakValidation:` (0x11c3f0); `+deviceOrientation` (0x11c410) |
| `BDInstallNetworkUtility` | `+isJailBroken` (0x12199c) |
| `BDUGShareBaseUtil` | `+_shouldHandleJailBrokenCase` (0x1219d0); `+isJailBroken` (0x1219fc) |
| `BGAdDeviceUtils` | `+isJailbroken` (0x122294) |
| `BLYDevice` | `-isJailbroken` (0x11cb94) |
| `BSG_KSSystemInfo` | `+isJailbroken` (0x11c48c) |
| `DeviceFingerPrint.DeviceInfo` | `-hasVpn` (0x115fe0); `-isJailBreak` (0x116000); `-proxyStatus` (0x116020) |
| `EFBreakTheCageChecker` | `+isJailBreakPath` (0x11c8bc); `+isJailBreakCydia` (0x11c8dc); `+isJailBreakAppName` (0x11c8fc); `+isJailBreakDYLD` (0x11c91c); `+isJailBreakPath_new` (0x11c93c); `+isJailBreakCydia_new` (0x11c95c); `+isJailBreakDYLD_new` (0x11c97c); `+isJailBreakLibs_new` (0x11c99c); `+isJailBreakHookNSFileManager_new` (0x11c9bc); `+isJailBreakHookC_new` (0x11c9dc) |
| `FFMClassOneFour` | `-cofoSymbolZeroTwo` (0x11c750) |
| `FFMClassZeroOne` | `-czoSymbolZeroSix` (0x11c728) |
| `GADevice` | `+isJailbroken` (0x116cac); `-checkJailbroken` (0x116ccc) |
| `GT3DataBase` | `-mobileInfo` (0x116c80) |
| `HMDLaunchTimingUserTrace` | `+startTraceUseProcExec` (0x1220d4); `+startSpanWithTaskName:` (0x1220f4); `+endSpanWithTaskName:` (0x122114) |
| `IGLocationTrackingService` | `-start` (0x11ca04) |
| `ISDeviceInfoService` | `-jailBroken` (0x11cb44); `-jailBroken` (0x1222bc) |
| `JBChecker` | `+mflsfdRfewqe` (0x11c670) |
| `JailMonkey` | `-isJailBroken` (0x11ca2c); `-canMockLocation` (0x11ca4c); `-canFork` (0x11ca6c); `-canViolateSandbox` (0x11ca8c); `-isDebugged` (0x11caac) |
| `MOBFDevice` | `+hasJailBroken` (0x11c508) |
| `MPDevice` | `+jailbrokenInfo` (0x11c380) |
| `MRDeviceUtils` | `+isJB` (0x116d54) |
| `MTGDeviceHandler` | `+isVpOn` (0x11cbc4); `+isProOn` (0x11cbe4) |
| `MTGDeviceInfo` | `-returnDeviceInfoDic` (0x11cc0c) |
| `MTRGDeviceUtils` | `+isJB` (0x116d7c) |
| `MWFmMDM5OTk2ZTdkMWY4ZmUy_EC` | `+load` (0x12216c) |
| `MiHoYoDeviceInfo` | `-isConnectedToProxy` (0x116c58) |
| `MobClick` | `+isJailbroken` (0x11c5cc) |
| `NGMzNzhjNmI0NDQyMzdiNTc0_EC` | `+load` (0x122194) |
| `NzY1YjdiMzkwYzc2N2U5YWMz_EC` | `+load` (0x1221bc) |
| `OKBCydia` | `+isJailbroken` (0x11c55c) |
| `OKEnvironment` | `-isOKCoin` (0x11c588); `-isJailbroken` (0x11c5a4) |
| `OneSignalJailbreakDetection` | `+isJailbroken` (0x11c4dc) |
| `PAGDeviceHelper` | `+bu_isJailBroken` (0x116cf8); `+bu_isJailBroken` (0x11cb70) |
| `PDXC` | `+load` (0x1222e8); `-disable_gdb` (0x122308); `-pc` (0x122328) |
| `PIPOStoreKitHelper` | `-isJailBroken` (0x121a24) |
| `PPRMOCMagnesCoreDataCollector` | `-isJailBroken` (0x11c694) |
| `PPRiskDeviceData` | `+isJailBroken` (0x11c5fc) |
| `PTURegulationManager` | `-startUpdateLocation` (0x121970) |
| `PluginShieldfraudPlugin` | `+registerWithRegistrar:` (0x122388) |
| `PuGo29z` | `+Xi05UCs` (0x11c7e8) |
| `RLMArray` | `-insertObject:atIndex:` (0x116c30) |
| `RLMRealm` | `+realmWithConfiguration:queue:error:` (0x116c08) |
| `SecurityWarnings` | `+isDeviceJailbroken` (0x11cadc); `+isHooked` (0x11cafc); `+isDebuggerAttached` (0x11cb1c) |
| `SensesDevice` | `-getDeviceIdfv` (0x116548); `+sharedInstance` (0x116568) |
| `SpectrumReachability` | `-isReachableViaWiFiNoVPN` (0x116abc); `-isConnectedViaVPN` (0x116adc) |
| `Talkable` | `-checkUrlScheme` (0x116b8c) |
| `UMUtils` | `+isDeviceJailBreak` (0x11c534) |
| `YMM_YX_SSJailbreakCheck` | `+jailbroken` (0x116d24) |
| `YjAxOGE4YTAwODQ5MjMxZTY2_EC` | `+load` (0x122144) |
| `turing_HIreYaasq8l5EBASEOS` | `+rootFlag` (0x11cc3c); `+injectingImageNames` (0x11cc5c) |

UIDevice 自定义检测方法同样未见 ProjectX 直接 Hook：`isJailbroken`、`+CPS_isJailBreak`、`+SHPSEC_riskInfoCryptInner:andLength:andGen:andKey:andThin:andAppId:andRiskToken:`、`stee_isJailbreak_1` 至 `_7`、`+btd_isJailBroken`。

## 5. 不能误判为 ProjectX 缺少的项目

1. **基础参数已经有。** IDFA、IDFV、设备名/型号、系统版本/build/kernel、序列号/IMEI 部分入口、开机时间/Boot UUID、WiFi SSID/BSSID、运营商/MCC/MNC、IP/网络类型、电池、容量、CPU/RAM、WebKit UA、Canvas/Audio/WebGL/字体指纹等均能在活动源码找到实现；只可能是额外入口、字段或一致性不足。
2. **档案管理不是全缺。** 新建/切换/重命名/单条删除/搜索与沙盒数据备份恢复已有；缺口是 ZIP 传输、禁用时间、顺序命令等。ProjectX 的“删除全部”目前也有 TODO，不能按 UI 算完成。
3. **HTTP 接口不是缺口。** ProjectX 已有 8888 后台 HTTP 接口。GPT 的“启用http脚本指令”菜单无法证明已运行 HTTP 服务；已确认的是 GPT URL scheme 命令。
4. **没有把历史空文件算作完成。** ProjectX PhoneInfo 有 keychainUUID/appGroupUUID/coreDataUUID/appInstallUUID/appContainerUUID 字段，不代表有 Keychain/AppGroup/CoreData 等对应完整 Hook。另一方面，GPT 也没有证实这些 UUID 隔离 Hook，所以不将它们列为本次“GPT 领先”的已确认项。
5. **MG/IOKit/IMEI 仅保留候选。** GPT 导出 `new_MGCopyAnswer_internal`、`new_MGCA`、`new_IORegistryEntryCreateCFProperties`、`new_IORegistryEntrySearchCFProperty`、`new_CTServerConnectionCopyMobileIdentity`、`new_isPlatformVersionAtLeast`、`new_GetMethodImp`、`new_dladdr` 等替换函数；本轮没有在恢复的注册调用及 fishhook 表中证实这些函数的安装路径。因此不能写成 GPT 已全面 Hook MobileGestalt/IMEI/UDID/MAC。ProjectX 的 MGCopyAnswer 代码则明确整段注释。
6. **GPT 的菜单也可能只是占位。** 飞行模式、极限模式、地图设置、扫码导入、网页文件管理、声音提示等不能只靠 UI 文案认定实现；设置代码包含“该功能还未开发”分支。本清单没有将这些无充分实现证据的菜单列为已确认缺口。
7. **GPT 的空方法不少。** 例如 AppDataCleaner 的 `clearPushNotificationData:`、`clearBluetoothData:`、`clearDNSCache:` 等只有 ret；GPT 主界面若干 IBAction 如 `doNewPhone:`、`doRebootSpringBoard:` 也只有 ret，虽然另有非空 job 方法及 URL 命令。方法存在不等于用户按钮确实接通。
8. **不声称清理/规避必然成功。** GPT 的 `contentsOfDirectoryAtPath:err:` selector 与系统通常的 `error:` 拼写不一致；定位回调中还有明显随机偏移逻辑。本分析只确认代码内容和相对缺口，不把这些实现当成高质量或全系统兼容的保证。
9. **数据库不可直接比条目。** GPT DeviceInfo.db 不是明文 SQLite，包内有 SQLCipher 相关代码；未解密，不能声称其机型/系统库一定比 ProjectX 更全。ProjectX IOS.db 的 KMDevSpecial 有 549 条，但参数生成器没有查询该表。

## 6. 建议补齐顺序（只列工作项，本次未改代码）

1. 参数模型与 UI：定位、地址、时区；修正 `nativeScale`，补主机名/CPU/网络 C 入口，保证配置到实际返回值的一致性。
2. 备份基本闭环：实现现有导入导出和批量删除占位；补 AppGroup/扩展容器、文件保留规则；钥匙串备份恢复先确认实际设计。
3. 扩充随机策略：机型/OS 多选与权重、机型+OS 特例 RAM、WiFi/5G 比例。
4. 对照需要支持的具体 App 再评估检测类和 SDK 适配；按目标版本验证，避免照搬整张 SDK 类名表。

## 7. 交付物与复核入口

- 解包目录：[rootfs](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/rootfs)；控制信息：[control](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/control)。
- 功能差异 CSV：[GPT_vs_ProjectX_功能差异.csv](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/GPT_vs_ProjectX_功能差异.csv)（29 项，含待确认项）。
- Hook 差异 CSV：[GPT_vs_ProjectX_Hook差异.csv](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/GPT_vs_ProjectX_Hook差异.csv)（235 注册调用点 + 19 fishhook 表项，合计 254 行；没有按独立功能去重）。
- 原始调用点：[tweak.hook_registrations.csv](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/evidence/tweak.hook_registrations.csv)；fishhook 表：[tweak.fishhook_entries.csv](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/evidence/tweak.fishhook_entries.csv)。
- 完整注释反汇编：[tweak.annotated.txt](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/evidence/tweak.annotated.txt)、[app.annotated.txt](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/evidence/app.annotated.txt)；重点片段：[key_tweak_excerpts.txt](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/evidence/key_tweak_excerpts.txt)。
- App 方法摘要：[app.method_summary.txt](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/evidence/app.method_summary.txt)；ProjectX 活动 Logos/手动电池入口索引：[projectx_active_hooks.json](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/evidence/projectx_active_hooks.json)。后者不含所有手写 C 注册，C 入口在差异表中另行核对。
- 提取脚本：[analyze.py](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/analyze.py)；对比报告生成脚本：[build_report.py](/Users/ww/Desktop/IOSManager/analysis/gpt_2.14-602/build_report.py)。

自动提取采用线性寄存器常量传播，不能替代完整控制流反编译；手工审阅对动态 Metal/代理类、Memora 偏移等作了覆盖和注释。原始 CSV 中的 `?`/推导值不能当成最终运行时值；审阅后的差异 CSV 是对照入口。
