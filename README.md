<div align="center">

# ProcessKill

**A lightweight Android background process suppression daemon script**  
**适用于 Magisk / KernelSU / APatch 模块环境的轻量级后台进程压制脚本**

[![Shell](https://img.shields.io/badge/Shell-sh-brightgreen)](./processkill.sh)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84)]()
[![Module](https://img.shields.io/badge/Module-Magisk%20%7C%20KernelSU%20%7C%20APatch-blue)]()
[![License](https://img.shields.io/badge/License-MIT-yellow)](./LICENSE)
[![Stars](https://img.shields.io/github/stars/yourname/ProcessKill?style=social)](https://github.com/yourname/ProcessKill)
[![Last Commit](https://img.shields.io/github/last-commit/yourname/ProcessKill)](https://github.com/yourname/ProcessKill)

</div>

---

## 📖 Overview

`ProcessKill` 是一个面向 Android 模块环境设计的 Shell 守护脚本，用于周期性扫描系统进程，并根据一套可配置规则，对符合条件的后台进程进行压制或清理。

与简单粗暴的“全杀后台”不同，`ProcessKill` 更强调：

- **可配置**
- **可热重载**
- **可追踪**
- **默认保守**
- **尽可能降低前台干扰**

它主要通过以下信息进行判断：

- `/proc/[pid]/cmdline`
- `/proc/[pid]/oom_score_adj`
- `/proc/[pid]/cpuset`
- `dumpsys` 获取的前台应用信息
- 用户配置的黑白名单

---

## ✨ Highlights

- 守护进程自管理，避免重复启动
- 开机完成后延迟运行，减少系统初始化阶段干扰
- 支持黑名单 / 白名单
- 支持前台应用保护
- 支持 OOM 阈值控制
- 支持深度压制模式
- 支持运行中热重载配置
- 支持日志记录与自动裁剪
- 纯 Shell 实现，结构简单，便于二次修改

---

## 📚 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [How It Works](#-how-it-works)
- [Project Structure](#-project-structure)
- [Configuration](#-configuration)
- [Configuration Reference](#-configuration-reference)
- [Blacklist / Whitelist](#-blacklist--whitelist)
- [Rule Priority](#-rule-priority)
- [Foreground App Protection](#-foreground-app-protection)
- [Logging](#-logging)
- [Hot Reload](#-hot-reload)
- [Installation](#-installation)
- [Usage](#-usage)
- [Recommended Settings](#-recommended-settings)
- [Compatibility](#-compatibility)
- [FAQ](#-faq)
- [Roadmap](#-roadmap)
- [Disclaimer](#-disclaimer)
- [License](#-license)

---

## 🚀 Features

### 1. Daemonized Self-Management
脚本启动时会先检查系统中是否已存在名为 `processkill` 的守护实例。  
如果已存在，则直接退出；如果不存在，则自动以 daemon 方式重新拉起自身，避免重复运行。

---

### 2. Boot Completion Awareness
脚本不会在系统刚开机时立即压制后台，而是先等待：

```sh
getprop sys.boot_completed
