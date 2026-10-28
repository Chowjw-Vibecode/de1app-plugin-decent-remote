# Usage by country / 使用地区统计

[English](#english) · [中文](#中文)

## English

Usage statistics help us understand where Decent Remote is used. They count installations by country or region. A random installation ID prevents double-counting; names, accounts, access keys, profiles and shot records are not sent.

The plugin sends only its random ID to the configured HTTPS service. Cloudflare determines the country from the request. D1 stores the ID's hash, country, and first and latest update times. The [GitHub summary page](https://chowjw-code.github.io/de1app-plugin-decent-remote/) contains country totals and 30-day active-installation counts, with no installation identifiers. Counts are installations, not people; VPNs and reinstalls can affect them. Our application does not store raw IP addresses; Cloudflare processes network information to serve requests.

The first update is attempted while de1app is idle or asleep, at least one minute after the plugin starts. After a successful update, the next is due in seven days. Failures wait at least 24 hours before another attempt. Statistics run in a background thread and do not control the machine.

**The release uses the deployed [HTTPS service](https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary).** Remote control works independently of the statistics service.

### Configuration

There is no additional screen, switch or first-run dialog. In `plugins/decent_remote/settings.tdb`:

- `usage_endpoint`: defaults to `https://decent-remote-usage.decent-remote-stats.workers.dev/v1/check-in` when the setting is absent. An explicitly empty value (`{}`) disables network updates. Existing values are preserved.
- `usage_enabled 1`: allow statistics when a valid endpoint is configured. Set it to `0` to disable them, then restart de1app while idle. Retain the rest of the configuration.

Preserve `usage-state.tdb` when updating the plugin. It contains the random ID and update times; deleting it creates a new installation identity. Neither state nor settings files are included in release archives. If Tcl Thread, TclCurl or de1app's `allcerts.pem` trust store is unavailable, statistics are skipped; the control API still works.

## 中文

使用地区统计用于了解 Decent Remote 在各地的使用情况，按国家／地区汇总安装数量。随机安装编号用于去重，不发送姓名、账户、访问密钥、曲线或出杯记录。

插件仅向配置的 HTTPS 服务发送随机编号。Cloudflare 根据请求判断国家／地区，D1 保存编号摘要、地区及首次和最近更新时间。[GitHub 汇总页](https://chowjw-code.github.io/de1app-plugin-decent-remote/)只展示地区总量和近 30 天活跃安装数，不包含安装编号。安装数量不等于人数，VPN 和重新安装可能影响结果。我们的应用不保存原始 IP；Cloudflare 会处理请求所需的网络信息。

插件启动至少一分钟后，首次在 App 待机或休眠时尝试更新；成功后间隔七天，失败后至少隔一天再试。统计在后台线程进行，不控制咖啡机。

**发布版已配置部署完成的 [HTTPS 服务](https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary)。**远程控制独立运行，不依赖统计服务。

### 配置

不增加页面、开关或首次使用弹窗。在 `plugins/decent_remote/settings.tdb` 中：

- `usage_endpoint`：未设置时使用 `https://decent-remote-usage.decent-remote-stats.workers.dev/v1/check-in`。显式设为空值 `{}` 则不联网；已有值保持不变。
- `usage_enabled 1`：配置有效地址后允许统计。改成 `0`，再于待机时重启 App，即可停用；保留其他配置项。

升级时保留 `usage-state.tdb`。它保存随机编号与更新时间，删除会生成新的安装身份。发布包不包含这个文件或实际设置。若缺少 Tcl Thread、TclCurl 或 App 的 `allcerts.pem` 证书文件，统计跳过，不影响控制接口。
