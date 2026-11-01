# SDK 方法适配明细

F14/F15 已从按 selector 名称猜测改为逐目标行为表。基线 60 个 SDK 类、94 个方法，加 UIDevice 10 个和 OpenUDID 1 个，共 **105 个目标均有专用行为分类**。目标类不存在时等待后续镜像加载；方法签名不匹配时保留原行为并记录 `signature-mismatch`。

这表示源码存在可执行适配器，不代表任意 App/SDK 版本已真机验证。不能从模拟类全部安装成功推导所有实际 SDK 都兼容。

## 新增独立开关

均位于“参数与工具”，默认关闭，且须同时开启 `sdkCompatibility`。

| runtime 字段 | 作用 |
|---|---|
| sdkSuppressCollectors | 跳过 Talkable、IGLocation、HMD 采集入口 |
| sdkSuppressInitialization | 跳过表内初始化/注册入口；不撤销已经执行的初始化 |
| sdkBlockRealmWrites | 跳过 RLMArray insertObject，可能影响目标 App 数据保存 |
| sdkSuppressAttribution | AFSDKiAdClient 返回 nil，可能影响广告归因 |
| sdkRewriteMetadata | FFM NETS 数字尾段、RDATES 使用当前 IDFV/IDFA 产生稳定变化 |

NETS 的 VPN 接口过滤使用 `maskProxy`。GT3 的 jdb/deb、MP 的 cydia 使用 `maskEnvironment`。清除开关或关闭 SDK 兼容时调用原方法。OpenUDID 配置独立生效。

## 首次自动初始化的修复

生产代码在 libobjc 初始化分发函数进入 `prepare_load_methods` 之前，同步安装五个目标的 `+load` 适配器。
先通过明确的私有符号名查找入口；找不到时仅接受经严格指令校验的 ARM64 `_objc_load_image` 导出桥，
核对参数转发、栈结构、分支、返回和同一 libobjc 可执行映像范围。支持旧的 path/header 与新的 info 指针两种 ABI，
不使用固定地址/偏移，不匹配时保留原行为。见 `hooks/PXSDKEarlyLoad.m`。

这次使用真实 macOS arm64 函数 Hook 后端加载实际 dylib，而非手动模拟调用 +load：

| 场景 | 五个目标各自的原初始化次数 | 结果 |
|---|---|---|
| 开启初始化抑制 | 0 | 自动首次调用被接管 |
| 关闭初始化抑制 | 1 | 原初始化执行一次 |
| 工作线程加载并嵌套 dlopen | 0 | 自动计数及外层加载上下文恢复正确 |
| 强制后端不可用 | 1 | 降级到普通发现，不伪报首次拦截 |
| 初始化后再启用早期入口 | 保持原先的 1 | 不重放或撤销历史初始化，后续调用正常适配 |

非目标类和嵌套子库的初始化各执行一次。真实动态库测试还验证了关闭开关后的原调用恢复。
`PXSDKCompatibilityReport` 中的 `early-load-installed` 表示早期方法已安装；
只有实际观察到自动调用后 `loadTimingUnverified` 才变为 false，另外记录自动、抑制和转发计数。
日志 `early +load dispatcher: unavailable` 表示当前后端或运行时入口形式不受支持；需保留原行为，不能认定首次拦截成功。

[Apple 的初始化实现](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.mm)显示，
初始化分发会先捕获方法 IMP，再调用 +load，因此安装必须早于捕获阶段。
没有在持有内部运行时锁的 `objc_addLoadImageFunc` 回调中扫描/安装方法。
已经早于插件接管执行的初始化无法撤销，修改开关后须重启目标 App；iOS 真机与各注入器的启动次序仍待验证。

## 验证与复现

生产引擎配合 macOS Objective-C 模拟类验证 105 个目标安装、返回类型、专有字典、调用次数、NSError**、
继承 super、异常帧恢复及并发。独立 ABI 测试覆盖 11 种整数宽度/符号、float 时间、不兼容签名拒绝，
以及导出桥的合法/损坏指令序列。默认 `python3 tests/run_tests.py` 共 849 项检查。

原生加载验证使用 Dobby 作为 **macOS 测试专用** 的函数 Hook 后端，提交固定为
`5dfc8546954ce3b3198132ab13fddb89ee92cdd7`。可将其 arm64 静态库路径传给：

```sh
PROJECTX_TEST_HOOK_LIBRARY=/path/to/libdobby.a python3 tests/run_tests.py
```

这一路径共 918 项检查，包含真正自动触发的初始化、开关关闭、后端失败、嵌套/多线程和延迟接管。
iOS 生产目标沿用已有 Substrate/兼容后端，不依赖 Dobby。未进行 iOS 真机安装验证。

## 逐方法行为

| 类 | 方法 | GPT 替换函数 | 当前实现 |
|---|---|---|---|
| `DeviceFingerPrint.DeviceInfo` | `-hasVpn` | `0x116f6c` | 代理兼容开启时返回 0/nil |
| `DeviceFingerPrint.DeviceInfo` | `-isJailBreak` | `0x116f90` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `DeviceFingerPrint.DeviceInfo` | `-proxyStatus` | `0x116fb4` | 代理兼容开启时返回 0/nil |
| `SensesDevice` | `-getDeviceIdfv` | `0x118898` | 返回当前档案的 IDFV 字符串；关闭 SDK 兼容时执行原方法 |
| `SensesDevice` | `+sharedInstance` | `0x1188d4` | GPT 是日志+原调用；保持原对象，不把实例当字典改写 |
| `SpectrumReachability` | `-isReachableViaWiFiNoVPN` | `0x119de0` | 代理兼容开启时按当前档案网络类型返回是否 WiFi |
| `SpectrumReachability` | `-isConnectedViaVPN` | `0x119e00` | 代理兼容开启时返回 0/nil |
| `ABKLocationUtilities` | `+isValidLocationAndAccurateEnough:` | `0x119e20` | 定位配置存在时返回有效；参数必须是对象 |
| `ABKLocationUtilities` | `+locationIsValidWithLatitude:longitude:` | `0x119e40` | 定位配置存在时返回有效；两个坐标必须均为 double |
| `Talkable` | `-checkUrlScheme` | `0x119e9c` | sdkSuppressCollectors 独立开启时跳过；默认原方法 |
| `AFSDKiAdClient` | `-appleAdsAttributionToken` | `0x119ea0` | sdkSuppressAttribution 开启时返回 nil；默认保留真实 token |
| `AFSDKDevice` | `+identifierForVendor` | `0x119ec0` | 返回当前档案的 IDFV 字符串；关闭 SDK 兼容时执行原方法 |
| `RLMRealm` | `+realmWithConfiguration:queue:error:` | `0x119f68` | GPT 是日志+原调用；保留配置、队列、NSError** 和返回值，原调用仅一次 |
| `RLMArray` | `-insertObject:atIndex:` | `0x119fd8` | sdkBlockRealmWrites 独立开启时跳过；默认保留对象和索引参数 |
| `MiHoYoDeviceInfo` | `-isConnectedToProxy` | `0x11a000` | 代理兼容开启时返回 0/nil |
| `GT3DataBase` | `-mobileInfo` | `0x11a020` | GT3 专用：jdb/deb 字符串为 0；代理开关下 py 为空对象 |
| `GADevice` | `+isJailbroken` | `0x11a0c4` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `GADevice` | `-checkJailbroken` | `0x11a0cc` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `PAGDeviceHelper` | `+bu_isJailBroken` | `0x11dd88` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `YMM_YX_SSJailbreakCheck` | `+jailbroken` | `0x11a0dc` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `MRDeviceUtils` | `+isJB` | `0x11a0e8` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `MTRGDeviceUtils` | `+isJB` | `0x11a0f0` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `MPDevice` | `+jailbrokenInfo` | `0x11d160` | MPDevice 专用：字典 cydia 为 @NO，保留其他字段 |
| `AppsFlyerUtils` | `+isVPNConnected` | `0x11d1b0` | 代理兼容开启时返回 0/nil |
| `AppsFlyerUtils` | `+isJailBreakon` | `0x11d1b8` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `AppsFlyerUtils` | `+isJailbrokenWithSkipAdvancedJailbreakValidation:` | `0x11d1c0` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `AppsFlyerUtils` | `+deviceOrientation` | `0x11d1c8` | 支持对象返回 p/lr 和整数返回；使用 interfaceOrientation 配置 |
| `AppsFlyerTracker` | `-setSkipAdvancedJailbreakValidation:` | `0x11d260` | 环境兼容开启时向原方法传 YES；关闭时保留参数 |
| `AppsFlyerTracker` | `-getTimePassedSinceLastLaunch` | `0x11d264` | 使用 timeSinceLastLaunch；支持 double/float 返回，允许 -1 |
| `BSG_KSSystemInfo` | `+isJailbroken` | `0x11d26c` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `AIMetaDataCollector` | `-getDeviceJailbrokenState` | `0x11d274` | 环境兼容开启时返回 NSNumber @NO；也支持整数签名 |
| `OneSignalJailbreakDetection` | `+isJailbroken` | `0x11d284` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `MOBFDevice` | `+hasJailBroken` | `0x11d28c` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UMUtils` | `+isDeviceJailBreak` | `0x11d294` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `OKBCydia` | `+isJailbroken` | `0x11d29c` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `OKEnvironment` | `-isOKCoin` | `0x11d2a4` | 环境兼容开启时返回 1（GPT 的正向环境谓词） |
| `OKEnvironment` | `-isJailbroken` | `0x11d2ac` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `MobClick` | `+isJailbroken` | `0x11d2b4` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `PPRiskDeviceData` | `+isJailBroken` | `0x11d2bc` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `ANSMetadata` | `-computeIsJailbroken` | `0x11d2c4` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `ANSMetadata` | `-isJailbroken` | `0x11d2cc` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `JBChecker` | `+mflsfdRfewqe` | `0x11d2d4` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `PPRMOCMagnesCoreDataCollector` | `-isJailBroken` | `0x11d2dc` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `FFMClassZeroOne` | `-czoSymbolZeroSix` | `0x11d398` | FFM 专用：NETS JSON/对象过滤 VPN 接口；独立开关下稳定改写 mac 数字尾段、RDATES 偏移排序 |
| `FFMClassOneFour` | `-cofoSymbolZeroTwo` | `0x11d8f4` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `PuGo29z` | `+Xi05UCs` | `0x11d914` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakPath` | `0x11dcc4` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakCydia` | `0x11dcd0` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakAppName` | `0x11dcdc` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakDYLD` | `0x11dce8` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakPath_new` | `0x11dcf4` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakCydia_new` | `0x11dd00` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakDYLD_new` | `0x11dd0c` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakLibs_new` | `0x11dd18` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakHookNSFileManager_new` | `0x11dd24` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `EFBreakTheCageChecker` | `+isJailBreakHookC_new` | `0x11dd30` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `IGLocationTrackingService` | `-start` | `0x11dd3c` | sdkSuppressCollectors 独立开启时跳过；默认原方法 |
| `JailMonkey` | `-isJailBroken` | `0x11dd40` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `JailMonkey` | `-canMockLocation` | `0x11dd48` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `JailMonkey` | `-canFork` | `0x11dd50` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `JailMonkey` | `-canViolateSandbox` | `0x11dd58` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `JailMonkey` | `-isDebugged` | `0x11dd60` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `SecurityWarnings` | `+isDeviceJailbroken` | `0x11dd68` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `SecurityWarnings` | `+isHooked` | `0x11dd70` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `SecurityWarnings` | `+isDebuggerAttached` | `0x11dd78` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `ISDeviceInfoService` | `-jailBroken` | `0x1227c8` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `BLYDevice` | `-isJailbroken` | `0x11dd90` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `MTGDeviceHandler` | `+isVpOn` | `0x11dd98` | 代理兼容开启时返回 0/nil |
| `MTGDeviceHandler` | `+isProOn` | `0x11dda0` | 代理兼容开启时返回 0/nil |
| `MTGDeviceInfo` | `-returnDeviceInfoDic` | `0x11dda8` | 保留原调用，递归处理设备标识/检测字典，支持数组嵌套 |
| `turing_HIreYaasq8l5EBASEOS` | `+rootFlag` | `0x11df28` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `turing_HIreYaasq8l5EBASEOS` | `+injectingImageNames` | `0x11df30` | 环境兼容开启时返回 nil |
| `PTURegulationManager` | `-startUpdateLocation` | `0x121ad8` | GPT 是日志+原调用；原调用一次；定位由 LocationHooks 统一处理 |
| `BDInstallNetworkUtility` | `+isJailBroken` | `0x121b14` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `BDUGShareBaseUtil` | `+_shouldHandleJailBrokenCase` | `0x121b1c` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `BDUGShareBaseUtil` | `+isJailBroken` | `0x121b24` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `PIPOStoreKitHelper` | `-isJailBroken` | `0x121b2c` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `HMDLaunchTimingUserTrace` | `+startTraceUseProcExec` | `0x12238c` | sdkSuppressCollectors 独立开启时跳过；默认原方法 |
| `HMDLaunchTimingUserTrace` | `+startSpanWithTaskName:` | `0x1223a8` | sdkSuppressCollectors 独立开启时跳过；默认原方法 |
| `HMDLaunchTimingUserTrace` | `+endSpanWithTaskName:` | `0x1223c4` | sdkSuppressCollectors 独立开启时跳过；默认原方法 |
| `YjAxOGE4YTAwODQ5MjMxZTY2_EC` | `+load` | `0x1223e0` | sdkSuppressInitialization 独立开启时跳过；+load 使用前置安装，未知入口明确降级 |
| `MWFmMDM5OTk2ZTdkMWY4ZmUy_EC` | `+load` | `0x1223e4` | sdkSuppressInitialization 独立开启时跳过；+load 使用前置安装，未知入口明确降级 |
| `NGMzNzhjNmI0NDQyMzdiNTc0_EC` | `+load` | `0x1223e8` | sdkSuppressInitialization 独立开启时跳过；+load 使用前置安装，未知入口明确降级 |
| `NzY1YjdiMzkwYzc2N2U5YWMz_EC` | `+load` | `0x1223ec` | sdkSuppressInitialization 独立开启时跳过；+load 使用前置安装，未知入口明确降级 |
| `AppsFlyerAES128Crypto` | `+encrypt:withObject:` | `0x1223f0` | GPT 是诊断日志；保持 data/key 和结果，原加密仅一次，不记录密钥或明文 |
| `ATURLArgumentModule` | `+getTrackCommonParameters` | `0x1226f4` | 保留原调用，递归处理设备标识/检测字典，支持数组嵌套 |
| `ALUtils` | `+isVPNConnected` | `0x12273c` | 代理兼容开启时返回 0/nil |
| `ALDataCollector` | `-requestParametersWithAdInfo:nested:` | `0x122744` | 原方法仅调用一次，保留 adInfo/nested；返回的设备参数字典统一处理 |
| `BGAdDeviceUtils` | `+isJailbroken` | `0x1227c0` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `PDXC` | `+load` | `0x1227d0` | sdkSuppressInitialization 独立开启时跳过；+load 使用前置安装，未知入口明确降级 |
| `PDXC` | `-disable_gdb` | `0x1227d4` | 环境兼容开启时跳过，关闭时调用原方法 |
| `PDXC` | `-pc` | `0x1227d8` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `ALISCSecurity` | `+isJailBreak` | `0x1227e0` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `PluginShieldfraudPlugin` | `+registerWithRegistrar:` | `0x1227e8` | sdkSuppressInitialization 独立开启时跳过；+load 使用前置安装，未知入口明确降级 |
| `UIDevice` | `-isJailbroken` | `0x118e5c` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UIDevice` | `-stee_isJailbreak_1` | `0x118ed8` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UIDevice` | `-stee_isJailbreak_2` | `0x118ee0` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UIDevice` | `-stee_isJailbreak_3` | `0x118ee8` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UIDevice` | `-stee_isJailbreak_4` | `0x118ef0` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UIDevice` | `-stee_isJailbreak_5` | `0x118ef8` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UIDevice` | `-stee_isJailbreak_6` | `0x118f00` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UIDevice` | `-stee_isJailbreak_7` | `0x118f08` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UIDevice` | `+CPS_isJailBreak` | `0x118e64` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `UIDevice` | `+btd_isJailBroken` | `0x118f28` | 环境兼容开启时返回 0/nil；整数按真实返回宽度调用，BOOL 单参数独立处理 |
| `OpenUDID` | `+value` | `0x1171a4` | 存在配置时返回 openUDID；独立于 SDK 兼容开关 |
