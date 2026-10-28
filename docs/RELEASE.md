# Introducing Decent Remote · 0.3.4

[中文说明](#中文说明) · [Install ZIP / 安装包](https://github.com/chowjw-code/de1app-plugin-decent-remote/releases/download/v0.3.4/decent_remote-v0.3.4.zip) · [Source ZIP / 源码包](https://github.com/chowjw-code/de1app-plugin-decent-remote/releases/download/v0.3.4/decent-remote-v0.3.4-source.zip)

## Your classic de1app workflow, with more ways to connect

Decent Remote brings the controls and data of classic de1app to a browser—and makes them available to AI agents through a documented HTTP API.

Keep the app, profiles and shot history you already use. Open a larger screen to adjust a recipe, work through an advanced profile, or inspect a shot. Connect your own agent to help with analysis and authorized changes through the same native control path.

![Decent Remote dashboard](images/current-en-dark.png)

### A workspace for the whole adjustment cycle

- **See the machine:** temperature, pressure, machine flow, scale weight and the current recipe in one view.
- **Shape the next shot:** load one of five named favorites from the Current page; adjust dose, target yield and temperature; edit advanced stages; import Tcl or de1app v2 JSON profiles.
- **Keep experiments intentional:** preview, load, apply, save, save as and restore are separate actions.
- **Learn from the result:** inspect recorded chart samples, zoom, and download the tablet's original shot files.
- **Connect your tools:** query structured state, submit changes and inspect request results through the API.
- **Make it yours:** English or Chinese, light or dark, favorites and supported native settings.

![Advanced profile editing](images/profiles-en-dark.png)

![Shot history and sample readouts](images/history-en-dark.png)

### Built around de1app

The plugin runs inside the classic app and uses its native control functions. No cloud account or separate server is required for remote control. Profiles and history stay in the app's existing folders.

The API distinguishes a request being accepted, values being read back from the app, and native profile frames being acknowledged. Those states are not presented as proof that a physical shot completed. The browser also blocks saving an edited profile while its transfer remains unconfirmed; retries require an explicit action.

Remote start is disabled by default. Wake, sleep and stop retain their native behavior, including group-head restrictions.

![Settings in the light theme](images/settings-en-light.png)

### Packages and setup

| Package | Use |
|---|---|
| `decent_remote-v0.3.4.zip` | Install in the classic de1app `plugins/` directory |
| `decent-remote-v0.3.4-source.zip` | Source, bilingual documentation, screenshots, offline tests and build tools |

Enable the plugin, restart de1app while idle, then open `http://TABLET_IP:8888/` on the same network. A fresh installation uses `admin1234`; change it in the tablet's Decent Remote settings. Existing installations retain their key. Preserve `settings.tdb` and any `usage-state.tdb` when updating.

Full steps: [English README](../README.md) · [API reference](API.md) · [Agent guide](AGENTS.md).

### Usage by country

The optional service groups installation counts by country or region. A random ID prevents duplicate counts; names, accounts, profiles and shots are not sent. The release includes the deployed service URL. [View country totals](https://chowjw-code.github.io/de1app-plugin-decent-remote/). [Details and configuration](USAGE.md).

### Tested compatibility

Version 0.3.4 is installed on one classic de1app **1.46.1.1 + Streamline** tablet. All 123 profiles were opened in both languages for read-only verification. The deployed statistics service also received an update from the native tablet client. Other configurations and physical start actions have not been verified. See [validation scope](VALIDATION.md).

Decent Remote is an independent community project, prepared under GPL-3.0-only. It does not replace firmware or promise every feature of newer apps. This package is for classic de1app, not Decaid.

*All screenshots show the actual dashboard with synthetic demonstration data. They are interface examples, not measured extractions.*

## 中文说明

### 保留熟悉的 de1app，打开新的使用方式

Decent Remote 为经典 de1app 增加浏览器工作台和 HTTP 接口。你可以在更大的屏幕上查看机器、调整配方、编辑曲线和复盘出杯，也可以让自己的 AI Agent 通过接口协助分析与调整。

项目始于两个想法：让老 App 用户尽可能获得更多新版 App 式的远程控制体验；让习惯用 AI Agent 研究咖啡的人，有一条直接、可查询执行结果的机器交互路径。

![Decent Remote 中文界面](images/current-zh-dark.png)

**这一版覆盖了从设置到复盘的日常流程：**

- 读取温度、压力、机器流量、秤重和当前配方。
- 从主屏五个常用按钮直接载入曲线，调整粉量、目标出液与温度，编辑高级分段，导入本地 Tcl／JSON 曲线。
- 分开处理预览、载入、临时应用、保存、另存和恢复。
- 查看历史曲线、逐点读数、放大和下载原始文件。
- 设置常用、预热、休眠、亮度、充电及定时唤醒。
- 通过 API 读取、修改和查询请求结果，供自有工具与 Agent 接入。

插件在 de1app 内运行，沿用原生控制方法。远程控制不需要云端账号或独立服务器；曲线和历史继续保存在原目录。支持中英文和深浅色切换，用户自定义名称保持原样。

安装使用 `decent_remote-v0.3.4.zip`，放入 `plugins/` 目录，启用后于待机时重启 App。在同一网络打开 `http://平板IP:8888/`。全新安装默认密钥 `admin1234`，可在平板插件设置页修改；更新时保留 `settings.tdb` 与已有的 `usage-state.tdb`。

使用地区统计按国家／地区汇总安装数量，随机编号用于去重，不发送姓名、账户、曲线或出杯记录。发布版已配置正式统计服务地址。[查看地区汇总](https://chowjw-code.github.io/de1app-plugin-decent-remote/)。[统计说明](USAGE.md)。

**已验证环境：classic de1app 1.46.1.1 / Streamline。** 0.3.4 已安装到一台 classic de1app 1.46.1.1 / Streamline 平板，123 条曲线已逐条完成中英文只读预览核对；平板原生统计客户端也已成功连接正式服务。远程启动默认关闭；本轮未启动出水、蒸汽或磨豆。

[完整中文说明](../README.zh-CN.md) · [接口文档](../API.md) · [验证范围](VALIDATION.md) · [更多截图](SCREENSHOTS.md)
