# Compatibility and migration / 兼容与迁移

[English README](../README.md) · [中文 README](../README.zh-CN.md)

## Supported baseline / 已验证基础环境

| Component / 组件 | Scope / 范围 |
|---|---|
| App | classic de1app 1.46.1.1 |
| Skin / 皮肤 | Streamline; favorites and recipe shortcuts use its native functions / 常用与快捷值依赖该皮肤原生方法 |
| Runtime / 运行环境 | Tcl 8.6, de1app native libraries and bundled wibble; supplied by the tested App / 由已测 App 提供 |
| Browser / 浏览器 | Chromium checked offline; other browsers need separate verification / Chromium 已离线验证，其他浏览器待测 |
| Other app releases / 其他版本 | Not yet verified / 尚未验证 |
| Decaid | Not supported by this package / 本包不是 Decaid 插件 |

## Existing remote plugins / 已有远程插件

If migrating from `advanced_rest_api`, `web_api` or the earlier standalone `hds_soft_sleep`, disable those installed plugins, then enable `decent_remote` and restart de1app while idle. Keep their files and settings if you want to roll back. They must not run alongside this plugin.

如果装有上述旧插件，先停用，再启用 `decent_remote` 并在待机时重启 App。保留旧文件和设置便于回退，不要同时启用。

Decent Remote implements compatible Advanced REST API paths and fields for existing clients. It does not load that plugin's code. On first configuration, it can read a valid authenticated key and port from the old plugin's settings as data; it does not execute or rewrite that file. An invalid existing key causes startup to fail instead of silently falling back to the default.

旧路径与字段的兼容用于已有客户端迁移，不依赖运行旧插件。首次配置可读取旧插件有效的鉴权密钥与端口，仅按数据读取，不执行或改写旧文件。已有密钥不合法时拒绝启动，不静默回退默认密钥。

## Optional integrations / 可选集成

- **DYE / SDB:** additional history workflows; missing dependencies return a clear unsupported response. / 扩展历史工作流，缺失时返回明确的不可用结果。
- **Decent/HDS scale soft sleep:** disabled on a fresh install. Requires a compatible scale and native scale functions; `keep_scale_on` and connection conditions govern behavior. / 新安装默认关闭，需要兼容秤及原生方法，受保持秤连接和实际连接条件控制。
- **Flow compensation (`flow_lut`):** query the already-installed plugin and change its enabled flag. The package does not include a calibration map or rewrite factory calibration. / 只查询已安装插件并切换其开关，不附带校准表，不改官方倍率。
- **Grinder bridge:** retained for existing API clients, requires the separate `crystal_grinder` plugin. Only state queries and stop remain available; grinder start requests are rejected. There are no grinder controls in the dashboard and that plugin is not bundled. / 仅保留现有接口的状态查询和停止功能，磨豆启动请求被拒绝；需单独的小方插件，网页没有磨豆控制，本包不附带该插件。

## Configuration / 配置

The plugin creates `settings.tdb` on first use. Updates must preserve it. / 首次使用自动创建配置，更新时须保留。

| Key / 键 | Default / 默认 | Meaning / 含义 |
|---|---|---|
| `port` | `8888` | Tablet settings; 1024–65535; restart the app to apply / 平板设置页修改，重启 App 后生效 |
| `token` | `admin1234` | New installation only; 8–128 visible ASCII characters, no whitespace / 仅全新安装，无空白 |
| `hds_enabled` | `0` | Tablet settings; restart the app to apply / 平板设置页开关，重启 App 后生效 |
| `usage_endpoint` | Deployed Cloudflare service / 已部署的 Cloudflare 服务 | Defaults to `https://decent-remote-usage.decent-remote-stats.workers.dev/v1/check-in`; an explicit empty value disables updates / 缺省使用正式统计地址，显式空值不联网 |
| `usage_enabled` | `1` | Allow statistics when an endpoint is configured; `0` disables it / 配置地址后允许统计，`0` 停用 |

The tablet settings page provides the access key, HDS sleep/wake and port controls. Save returns to the plugin list; Cancel discards edits. Port and HDS changes take effect after restarting de1app. Saving does not start the machine.

For offline setup, `python3 tools/create_config.py --output settings.tdb` creates a new file without overwriting one. `--random-key` generates a key; `--hds` enables the optional scale integration. This tool never connects to de1app. Do not include your configuration in a public repository.

离线配置工具仅生成文件，不连接设备、不覆盖已有文件。它不是安装必需步骤。密钥、HDS 联动和端口均可在平板插件设置页修改，无需编辑配置文件。保存会返回插件列表，取消会放弃修改。

<a id="hds-scale-integration"></a>

## HDS scale integration / HDS 秤联动

HDS soft sleep is optional and disabled on a fresh install (`hds_enabled=0`). For a compatible scale, open the tablet’s plugin list → Decent Remote → Settings and turn on **HDS scale sleep/wake**, enable de1app’s keep-scale-on option, and restart de1app while idle. Pair the scale through de1app as usual. The plugin adds soft sleep/wake commands; it does not replace the native scale driver or automatically identify HDS hardware revisions. The earlier standalone implementation was physically checked with a scale reporting HDS 3.1.15; this is not a claim that every HDS revision has been tested.

全新安装默认关闭 HDS 软休眠（`hds_enabled=0`）。使用兼容秤时，打开平板插件列表 → Decent Remote → 设置，开启 **HDS 秤休眠联动**，开启 de1app 的保持秤开启选项，再于待机时重启 App。秤仍通过 de1app 正常配对。插件补充软休眠／唤醒指令，不替换原生驱动，也不自动识别 HDS 硬件版本。早期独立实现曾在报告 HDS 3.1.15 的秤上实测；不代表所有版本均已验证。

**Only for users of the earlier standalone HDS Soft Sleep plugin:** its behavior is now included in Decent Remote. Disable the standalone plugin before enabling this integration, so the same native methods are not wrapped twice.

**仅适用于曾安装独立版 HDS Soft Sleep 的用户：** 此功能已合并到 Decent Remote。启用本集成前停用独立插件，避免重复接管同一原生方法。普通新用户无需安装或寻找该旧插件。
