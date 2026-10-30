# GitHub Actions 编译

在仓库 **Actions → Build Theos packages** 中选择 **Run workflow**，或向
`main` / `master` 推送代码、提交 Pull Request，自动编译现有的三种 `TYPE` 模式。
成功运行后，在页面底部 **Artifacts** 下载对应压缩包并解压获得 `.deb`：

| Artifact | 命令 | 打包 scheme |
| --- | --- | --- |
| `ProjectX-rootfull` | `make TYPE=0 ARCHS=arm64 FINALPACKAGE=1 package` | 默认 |
| `ProjectX-rootless` | `make TYPE=1 ARCHS=arm64 FINALPACKAGE=1 package` | rootless |
| `ProjectX-roothide` | `make TYPE=2 ARCHS=arm64 FINALPACKAGE=1 package` | roothide |

`rootfull` 沿用工程名称，等同于 rootful。默认本地模式仍是 `TYPE=1`。
切换模式前先运行同模式的 `make TYPE=… ARCHS=arm64 clean`。
失败时下载 `build-log-<模式>` 或直接查看失败步骤。Artifacts 保留 14 天。
无需配置 Apple 证书或仓库 Secrets；Theos 使用 ldid 和工程现有 entitlements 签名。

## 工具链和依赖

- macOS 15 runner、Xcode 16.4、GNU make、ldid、xz。
- 递归安装 `roothide/theos`，提供源码所需的 `roothide.h`。
- 从 `theos/sdks` 安装含私有框架符号的 `iPhoneOS16.5.sdk`。
- 使用已入库的 `libs/libGCDWebServers.a` 和 `headers/GCDWebServers/`。
- 从固定提交源码编译 AltList 框架并安装到当前 runner 的 Theos；
  设备上需由包管理器安装 `com.opa334.altlist` 依赖。
- 保留原项目 `arm64` 架构；rootfull 为 iOS 13.0，其他为 iOS 15.0。
  Rootful 下限已与包内 GCDWebServers 静态库对齐，不再声明 iOS 12.0。
  workflow 不增加 arm64e 或修改注入范围。
- Theos 和 SDK 跟踪各自 master；安装步骤会打印实际提交 SHA，便于排查。

## 验证范围

CI 成功只证明当前源码可以编译打包，不代表已完成真机安装、启动或功能测试。
现有 control 描述、LaunchDaemon 和安装脚本主要按 Rootless 布局编写；
Rootful / RootHide 成品的设备安装路径和脚本兼容性需要单独验证。
子目录 `ProjectXTweak/Makefile` 没有被根 Makefile 引入，CI 使用根目录的
App、Tweak、Daemon 三个 target，不重复构建历史子目录。

## 回归测试

在 macOS 上运行 `python3 scripts/check_metadata.py` 和 `python3 tests/run_tests.py`。
测试直接编译生产代码的 Foundation 模块，使用临时目录和仅监听本机的 HTTP 测试服务，
覆盖 JSON 校验、HTTP 成功/错误/空响应、参数编码、连接失败，以及档案保存、加载、
清空、保存失败回滚与 ID 唯一性。不会连接手机或访问默认档案目录。

## 发布 Release

1. 同步修改 `control` 的 `Version` 和 `Info.plist` 的两个版本字段。
2. 更新 `CHANGELOG.md`，新增 `docs/releases/v<版本>.md`。
3. 推送 `v<版本>` 标签，或在主分支的发布提交信息中包含 `[release]`；
   也可在主分支 Actions 手动运行时勾选 `publish_release`。

通过回归测试和全部三种模式构建后，发布 job 才会创建对应 GitHub Release，
附加按模式命名的 `.deb` 和 `SHA256SUMS`。普通推送和 PR 不会发布。
发布 job 单独申请 `contents: write`，使用 GitHub 自带 token，无需额外 Secrets。
已发布版本不覆盖附件；版本标签若指向其他提交，流程会停止，需使用新版本号。
