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
- 保留原项目 `arm64` 架构和部署目标：rootfull 为 iOS 12.0，其他为 iOS 15.0。
  workflow 不增加 arm64e 或修改注入范围。
- Theos 和 SDK 跟踪各自 master；安装步骤会打印实际提交 SHA，便于排查。

## 验证范围

CI 成功只证明当前源码可以编译打包，不代表已完成真机安装、启动或功能测试。
现有 control 描述、LaunchDaemon 和安装脚本主要按 Rootless 布局编写；
Rootful / RootHide 成品的设备安装路径和脚本兼容性需要单独验证。
子目录 `ProjectXTweak/Makefile` 没有被根 Makefile 引入，CI 使用根目录的
App、Tweak、Daemon 三个 target，不重复构建历史子目录。
