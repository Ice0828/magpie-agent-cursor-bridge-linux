# Cursor · Magpie Bridge for Linux

<p align="center">
  <a href="README.md">English</a> | <b>中文</b>
</p>

专为 **Linux (x64 / arm64)** 平台深度打造的 Cursor · Magpie 协议桥接插件。让 Linux 下的 Cursor IDE 无缝使用 **Magpie** 网关中配置的全部大模型与智能路由组：模型菜单直接展示 Magpie 模型目录，隐藏 Cursor 默认 Auto 入口，保留 Cursor 原生登录与 Tab 补全。

---

## 一、 为什么选择 Linux 专属版？

原版（nodlles）与社区增强版均主要面向 macOS / Windows，在 Linux 平台上存在原生引擎缺失、系统守护空白或子代理假死等痛点。本工程专门针对 Linux 开发者环境打通全链路：

* 🐧 **Linux 原生系统守护（`systemd --user`）**：
  原生适配 Linux 用户服务管理体系，无需 root 提权即可实现登录后自动常驻后台、守护进程崩溃重启、日志由 `journalctl` 统筹审计。
* 🔐 **全发行版证书信任自动化**：
  自动适配 Debian/Ubuntu (`update-ca-certificates`)、RHEL/Fedora/CentOS (`update-ca-trust`)、Arch/Manjaro (`trust extract-compat`)，并协同配置 Cursor 本地 `argv.json` 的 `certificate-authority`，一键打通本地回环 TLS 代理。
* ⚡ **Multitask Subagent 后台多任务接管**：
  完整解决 Cursor 开启后台并发子代理时，子任务完成后卡在 “Stopped”、父 Agent 无法唤醒的问题。内部实现 Statsig `djb2` 哈希对齐，监听 `BackgroundTaskCompletionAction`，自动回写 `Success/Error` 状态并无缝拉起父 Agent 续写。
* 💾 **轻量级内存库模式（In-Memory SQLite）**：
  默认采用 `sqlite::memory:`（多连接共享缓存），所有临时会话、工具调用与 Checkpoints 均保留在内存中，进程退出即销毁，**彻底告别 `bridge.db` 动辄占用 2GB~5GB 的磁盘空间暴涨**；亦可通过环境变量一键切换回磁盘模式。
* 🚀 **Cursor 3.29+ / 3.30+ 协议零拷贝兼容**：
  不仅支持最新的 `data_binary` 原始 Protobuf 二进制上行编码，在 Rust 解码层采用 `Cow::Borrowed` 零拷贝借用，并全面补齐 3.29+ 新增 Protobuf 字段，免除 30 秒 “Connection stalled” 假死超时。
* 🎨 **模型名称智能短名化**：
  智能过滤冗长的多段式描述（如 `Opus · routing group · group/opus`），在 Cursor 菜单中仅展示核心名称（`Opus`, `Sonnet` 等），防止界面宽度受限截断。
* 📦 **轻量极简**：
  剔除所有跨平台的预编译 EXE 及无关脚本，仓库仅包含 Linux 原生组件与源码补丁，体积小巧敏捷。

---

## 二、 架构原理

```text
┌─────────────────────────────────────────────────────────────┐
│ Magpie Gateway                                              │
│  提供 127.0.0.1:3425/v1（OpenAI 兼容接口与模型目录）           │
└──────────────────────────┬──────────────────────────────────┘
                           │ 动态同步模型 / 转发请求
┌──────────────────────────▼──────────────────────────────────┐
│ 后台守护进程（bridge.js / systemd --user）                   │
│  ├─ 每 15 秒热同步 Magpie 模型列表 → effective.json          │
│  ├─ 管理生命周期，拉起原生无头引擎 cursor-magpie-bridge       │
│  └─ 备份与还原 Cursor 代理设置（settings-journal.json）      │
└──────────────────────────┬──────────────────────────────────┘
                           │ 进程派生
┌──────────────────────────▼──────────────────────────────────┐
│ 原生协议引擎（Rust + hudsucker，基于 cursor-byok 二次开发）    │
│  ├─ 本地 TLS MITM 代理（自动配置本地独立 CA）                 │
│  ├─ 解析 Cursor Connect/Protobuf 协议（data_binary 支持）    │
│  ├─ Multitask 后台子任务完成监听与父 Agent 唤醒状态机          │
│  └─ 内存库模式（In-Memory SQLite，零磁盘开销）                │
└──────────────────────────┬──────────────────────────────────┘
                           │ 本地回环代理
┌──────────────────────────▼──────────────────────────────────┐
│ Cursor IDE (Linux)                                          │
│  ~/.config/Cursor/User/settings.json (http.proxy)           │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、 安装与快速上手

### 1. 前置要求
- Linux 系统（已实测 Ubuntu / Debian / Fedora / Arch / Manjaro）；
- 已安装并登录 **Cursor**；
- 已安装并启动 **Magpie**，且至少配置了一个可用模型或智能路由组。

### 2. 极简 GUI 全自动安装（推荐，零终端命令）
1. **安装插件**：打开 Magpie 客户端 → 进入 **Plugins / 插件管理** → 填入 GitHub 仓库地址并点击安装：
   ```text
   github:Ice0828/magpie-agent-cursor-bridge-linux
   ```
2. **启用桥接**：
   - 打开 Magpie 的 **Agents** 页面，找到 **Cursor · Magpie Bridge**，**打开开关**并选择所需模型；
   - 插件将**全自动在后台静默完成**：原生引擎下载（内置镜像加速与 SHA256SUMS 动态校验）、CA 证书配置与 `systemd --user` 用户守护进程托管；
   - 首次连接就绪后，无需重启系统。
3. **在 Cursor 中使用**：
   - 打开 Cursor，点击对话面板或右下角的模型选择下拉框；
   - Magpie 的全部模型与路由组已自动呈现，点击即可畅快对话与编写代码！

---

### 3. CLI 命令行与开发者手动安装（备用）
若处于离线环境、调试开发或无需 Magpie GUI 的场景，可直接在终端操作：
```bash
# 进入插件目录一键安装配置并启动服务
./setup.sh setup

# 查看运行状态（返回 "state": "connected" 即说明桥接就绪）
./setup.sh status
```

---

## 四、 运维与常用命令

`setup.sh` 提供了便捷的 Linux 管理指令：

| 命令 | 说明 |
| :--- | :--- |
| `./setup.sh setup` | 安装服务、初始化本地 CA 证书并启动 |
| `./setup.sh status` | 查看桥接运行状态、当前模型及代理端口 |
| `./setup.sh start` | 启动 `systemd --user` 用户级后台守护服务 |
| `./setup.sh stop` | 停止后台守护服务 |
| `./setup.sh restart` | 重启后台守护服务 |
| `./setup.sh logs` | 实时查看 `journalctl` 服务运行日志 |
| `./setup.sh uninstall` | 卸载 systemd 服务并清理证书信任 |

亦可直接使用 Linux 标准 `systemd` 工具链统一审计与管理：
```bash
# 查看桥接服务状态
systemctl --user status local.magpie.cursor-bridge.service

# 实时跟踪日志
journalctl --user -u local.magpie.cursor-bridge.service -f

# 重启或停止服务
systemctl --user restart local.magpie.cursor-bridge.service
systemctl --user stop local.magpie.cursor-bridge.service
```

---

## 五、 环境变量配置

在启动前或在 `~/.config/systemd/user/cursor-magpie-bridge.service` 中可通过环境变量调整行为：

| 变量名 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `CURSOR_BRIDGE_RUN_MODE` | `lite` | `lite` 为轻量内存库模式（In-Memory SQLite，零磁盘占用）；设置为 `default` 会在 `data/bridge.db` 落盘持久化。 |
| `CURSOR_BRIDGE_SUBAGENT_MODE` | `async` | `async` 为支持 Multitask 后台子任务并唤醒父 Agent；若设为 `sync` 则强制所有子任务同步阻塞执行。 |
| `CURSOR_BRIDGE_PROXY_PORT` | 随机可用端口 | 指定固定回环代理端口，避免重启服务更换端口。 |

---

## 六、 如何重新构建原生引擎

本仓库采用确定性的 **Git Patch** 维护模式（所有 Rust 修改均保存在 [source.patch](source.patch) 中）：

```bash
# 运行构建脚本（拉取上游固定 baseline，打入 patch 并调用 cargo 编译 release）
./scripts/build-native.sh
```
编译成功后，产物将自动部署到 `bin/cursor-magpie-bridge`，并自动刷新 [integrity.json](integrity.json) 的 SHA-256 校验摘要。

运行测试套件：
```bash
npm test
```

---

## 七、 致谢与开源说明

本项目基于开源社区优秀工作的传承与改进，在此向相关作者致以诚挚感谢：

1. **原生协议核心**：[leookun/cursor-byok](https://github.com/leookun/cursor-byok) (v1.0.1) —— 提供了卓越的 TLS MITM 逆向与代理核心基础设施。
2. **插件生命周期与框架**：[nodlles/magpie-agent-cursor-bridge](https://github.com/nodlles/magpie-agent-cursor-bridge) (v0.2.2) —— 建立了 Magpie Agent 插件的最初架构与动态同步通道。
3. **增强版特性灵感**：[kingchen95272025/magpie-agent-cursor-bridge-enhanced](https://github.com/kingchen95272025/magpie-agent-cursor-bridge-enhanced) —— 提供了 Multitask 子代理完成唤醒状态机及 In-Memory SQLite 模式的架构思路。

---

## 八、 免责声明

本项目仅供个人在 Linux 环境下学习研究本地网络回环协议转译与大模型代理之用，不修改 Cursor 任何本体二进制文件，亦不绕过任何认证逻辑。请遵守各模型供应商的服务条款及 API 计费规范。
