# Usage by country / 使用地区统计

[English](#english) · [中文](#中文)

## English

Usage statistics help us understand where Decent Remote is used. They group reporting installations by country, state/province and city. A random installation ID prevents double-counting; names, accounts, access keys, profiles and shot records are not sent.

The plugin sends its random ID and version to the configured HTTPS service. The legacy Cloudflare endpoint relays the source IP through an authenticated channel to the domestic service. That service privately saves the ID hash, product, version, first/latest report times and latest valid public IP, its collection time and locally resolved country/region/city. It keeps no IP history and does not send IPs to third-party geolocation APIs. The [domestic page](https://home.zhouchenxing.com/usage-stats/) and [GitHub page](https://chowjw-vibecode.github.io/usage-stats/) publish aggregates only, without IPs or installation identifiers. Locations reflect network exits, not home addresses; VPNs and database errors can affect them. Existing records without IPs need another report to gain city details. Counts are installations, not people.

The first update is attempted while de1app is idle or asleep, at least one minute after the plugin starts. After a successful update, the next is due in seven days. Failures wait at least 24 hours before another attempt. Statistics run in a background thread and do not control the machine.

**The release uses the deployed [HTTPS service](https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary).** Remote control works independently of the statistics service.

### Configuration

There is no additional screen, switch or first-run dialog. In `plugins/decent_remote/settings.tdb`:

- `usage_endpoint`: defaults to `https://decent-remote-usage.decent-remote-stats.workers.dev/v1/check-in` when the setting is absent. An explicitly empty value (`{}`) disables network updates. Existing values are preserved.
- `usage_enabled 1`: allow statistics when a valid endpoint is configured. Set it to `0` to disable them, then restart de1app while idle. Retain the rest of the configuration.

Preserve `usage-state.tdb` when updating the plugin. It contains the random ID and update times; deleting it creates a new installation identity. Neither state nor settings files are included in release archives. If Tcl Thread, TclCurl or de1app's `allcerts.pem` trust store is unavailable, statistics are skipped; the control API still works.

## 中文

使用地区统计用于了解 Decent Remote 在各地的使用情况，按国家、省／州和城市汇总已上报的安装数量。随机安装编号用于去重，不发送姓名、账户、访问密钥、曲线或出杯记录。

插件向配置的 HTTPS 服务发送随机编号和当前插件版本。旧 Cloudflare 入口通过认证通道向国内服务转交连接源 IP。国内服务私下保存编号摘要、产品、版本、首次／最近上报时间，以及最新有效公网 IP、IP 采集时间和本地解析的国家、省市。不保留 IP 历史，不向第三方定位接口发送 IP。[国内统计页](https://home.zhouchenxing.com/usage-stats/)和 [GitHub 汇总页](https://chowjw-vibecode.github.io/usage-stats/)只展示汇总，不含 IP 或安装编号。位置反映网络出口，不等于住址，VPN 和定位库误差会影响结果。旧记录未保存 IP，需下一次上报补齐省市。安装数量不等于人数。

插件启动至少一分钟后，首次在 App 待机或休眠时尝试更新；成功后间隔七天，失败后至少隔一天再试。统计在后台线程进行，不控制咖啡机。

**发布版已配置部署完成的 [HTTPS 服务](https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary)。**远程控制独立运行，不依赖统计服务。

### 配置

不增加页面、开关或首次使用弹窗。在 `plugins/decent_remote/settings.tdb` 中：

- `usage_endpoint`：未设置时使用 `https://decent-remote-usage.decent-remote-stats.workers.dev/v1/check-in`。显式设为空值 `{}` 则不联网；已有值保持不变。
- `usage_enabled 1`：配置有效地址后允许统计。改成 `0`，再于待机时重启 App，即可停用；保留其他配置项。

升级时保留 `usage-state.tdb`。它保存随机编号与更新时间，删除会生成新的安装身份。发布包不包含这个文件或实际设置。若缺少 Tcl Thread、TclCurl 或 App 的 `allcerts.pem` 证书文件，统计跳过，不影响控制接口。

版本分布按每个安装最近上报的版本统计；旧客户端没有提供版本时显示未知。升级后首次空闲会补报版本，同一安装不会因升级重复计数。
