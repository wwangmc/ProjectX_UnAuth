# ProjectX UnAuth

[![Build Theos packages](https://github.com/wwangmc/ProjectX_UnAuth/actions/workflows/build.yml/badge.svg)](https://github.com/wwangmc/ProjectX_UnAuth/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/wwangmc/ProjectX_UnAuth)](https://github.com/wwangmc/ProjectX_UnAuth/releases/latest)

基于 [waruhachi/ProjectX](https://github.com/waruhachi/ProjectX) 的越狱 iOS 工程。
本分支移除了原项目的登录流程，并加入应用数据备份、钥匙串清理及参数来源设置。
工程由 **ProjectX 应用、ProjectXTweak 注入插件、ProjectXDaemon 后台服务**组成。

## 功能

GPT 对照改进的实现、使用入口与未完成项见 [功能说明](docs/GPT_FEATURES.md) 和 [TODOLIST](TODOLIST)。
设置页的“参数与工具”提供新增参数、随机策略和备份传输入口。

- 选择需要应用参数的 App 范围。
- 管理设备标识、设备型号、系统版本、网络和位置等参数。
- 创建、切换、重命名和删除档案，保存应用数据与对应参数。
- 按运营商和 iOS 版本范围生成参数，使用包内 `IOS.db` 数据源。

“一键新机”和切换备份会关闭选中的应用并执行数据备份/清理；失败会尝试回滚。
钥匙串密码代理默认关闭，开启后需要目标应用配合；其范围和未完成项见功能说明。操作前保留重要备份。

## 下载与安装

在 [GitHub Releases](https://github.com/wwangmc/ProjectX_UnAuth/releases/latest) 下载与你的越狱环境匹配的 `.deb`。
不要同时安装多个模式。包管理器需要能解析 `mobilesubstrate` 和 `com.opa334.altlist` 依赖；
RootHide 环境还需要使用与自身环境兼容的依赖版本。

| 文件后缀 | Make 参数 | 编译目标 | 验证范围 |
| --- | --- | --- | --- |
| `rootfull.deb` | `TYPE=0` | arm64 / iOS 13.0+ | CI 编译打包，真机未验证 |
| `rootless.deb` | `TYPE=1` | arm64 / iOS 15.0+ | CI 编译打包，真机未验证 |
| `roothide.deb` | `TYPE=2` | arm64 / iOS 15.0+ | CI 编译打包，真机未验证 |

`rootfull` 是工程沿用的拼写，含义为 Rootful。版本号和编译目标不能保证所有系统、设备或越狱的兼容性。
当前安装脚本和 LaunchDaemon 主要沿用 Rootless 布局，Rootful / RootHide 包仍需验证设备上的安装和启动。
当前只生成 arm64，不包含 arm64e 注入切片。

安装流程：

1. 用越狱环境的包管理器安装对应 `.deb` 及依赖，按提示刷新应用图标或重启用户空间。
2. 打开 ProjectX，在应用列表中选择范围，再配置参数。
3. 操作前确认档案和备份；重新启动目标 App 后检查参数效果。

Release 附带 `SHA256SUMS`，可在下载目录校验：

```sh
shasum -a 256 -c SHA256SUMS
```

## 数据与后台服务

- 档案和备份：`/private/var/mobile/Media/ProjectX/`，索引为 `profiles.json`。
- 参数数据库：包内 `Library/IOS.db`。
- 注入范围：对应安装前缀下 `Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.plist`。
- 后台服务：`ProjectXDaemon`，HTTP 端口 `8888`；应用通过 `127.0.0.1` 调用。

现有 HTTP 接口未实现鉴权，服务仅监听 `127.0.0.1`。新增统一命令和 URL 操作见功能说明。
升级前保留自己的备份目录；重新安装依赖不能恢复已清理的数据。

## 构建与测试

完整工具链说明见 [docs/BUILD.md](docs/BUILD.md)。Windows 可编辑源码并通过 GitHub Actions 编译；
本地 iOS 构建需要 macOS、完整 Xcode、RootHide Theos、补丁版 iOS 16.5 SDK，以及 AltList 开发框架。

```sh
# 默认 Rootless；切换模式时先清理
make TYPE=1 ARCHS=arm64 clean
make TYPE=1 ARCHS=arm64 FINALPACKAGE=1 package

# 在 macOS 上执行独立回归测试，不需要连接设备
python3 scripts/check_metadata.py
python3 tests/run_tests.py
```

Actions 支持推送、PR 和手动触发，先运行 Foundation 回归测试，再并行构建三种包。
普通运行在 Artifacts 提供 `.deb` 和日志，保留 14 天。
发布规则见 [构建文档](docs/BUILD.md#发布-release)，版本变化见 [CHANGELOG.md](CHANGELOG.md)。

## 目录

| 路径 | 内容 |
| --- | --- |
| 根目录 `*.m`、`*.h` | 应用界面 |
| `hooks/` | 注入逻辑 |
| `daemon/` | 后台接口、参数生成、应用数据操作 |
| `common/`、`model/` | HTTP、档案、设置与数据模型 |
| `headers/`、`libs/` | GCDWebServers 头文件和静态库 |
| `layout/` | 数据库、LaunchDaemon、安装脚本 |
| `tests/`、`scripts/` | 回归测试与版本校验 |

根 Makefile 构建应用、插件和后台三个 target；`ProjectXTweak/` 是未纳入当前根构建的历史子目录。

## 致谢

原工程：[waruhachi/ProjectX](https://github.com/waruhachi/ProjectX)。
构建和依赖：[Theos](https://github.com/theos/theos)、[RootHide Theos](https://github.com/roothide/theos)、
[AltList](https://github.com/opa334/AltList)。第三方代码和资源的权利归各自作者所有。
