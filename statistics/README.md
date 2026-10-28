# Decent Remote 使用地区统计

[English](README.en.md)

按国家／地区汇总安装数量，帮助了解 Decent Remote 在各地的使用情况。随机安装编号用于去重，不发送姓名、账户、密钥、曲线或出杯记录。

**Cloudflare Worker 与 D1 已部署，0.3.4 已配置正式服务地址。** [公开汇总页](https://chowjw-vibecode.github.io/de1app-plugin-decent-remote/)。

服务：`https://decent-remote-usage.decent-remote-stats.workers.dev`；[地区汇总](https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary)。部署冒烟验证了新增、去重、校验、删除和汇总导出；验证范围见 [VALIDATION.md](../docs/VALIDATION.md)。

## 数据流

`插件随机编号 → Cloudflare Worker → D1 地区记录 → 汇总接口 → GitHub Pages`

- 平板保存随机安装编号、上次尝试及成功时间；成功后七天更新一次，失败后至少隔一天重试。
- D1 保存编号的 SHA-256 摘要、国家／地区、首次及最近更新时间。它们是安装记录，不是账户或设备硬件身份。
- GitHub 页面只有地区数量、近 30 天活跃安装数量及汇总时间，没有安装明细。
- 国家／地区由 Cloudflare 请求元数据推定。VPN、重新安装和伪造请求可能影响结果；不是人数统计。应用数据库和日志不保存原始 IP，Cloudflare 会处理请求所需的网络信息。
- 无配置地址不联网。客户端用独立线程，缺少依赖时跳过；不影响本地控制，也不操作咖啡机。配置停用方法见安装包 `docs/USAGE.md`。

## 接口

| 方法与路径 | 用途 |
| --- | --- |
| `POST /v1/check-in` | 请求体仅为 `{"install_id":"32位随机小写十六进制"}`，同一编号只更新一条安装记录 |
| `DELETE /v1/check-in` | 同一请求体删除该安装记录，可重复调用 |
| `GET /v1/summary` | 返回地区安装数及近 30 天活跃安装数，不返回编号 |

以服务器收到请求的时间判断新旧。较早请求不能覆盖新地区；同一秒保留已有地区；首次时间取最早值。随机编号也用于删除自己的记录，应留在本地配置，不写进公开日志。

## 本地检查

在源码包根目录运行，需 Node.js 22.13+、Tcl 8.6/Tcllib、Python 3.10+：

```sh
node --test statistics/tests/worker.test.mjs
tclsh8.6 statistics/tests/client.test.tcl
python3 statistics/tests/export.test.py
```

SQL 使用内存 SQLite，客户端用模拟传输，均不连接真实服务。客户端运行时还需要 Tcl Thread、TclCurl 及 de1app 的 `allcerts.pem`。

## Cloudflare 配置

以下为自行托管的步骤；使用发布包的默认服务无需重复部署。本地构建不会部署云端：

1. 在 `statistics/` 中将 `wrangler.example.toml` 复制为 `wrangler.toml`。
2. 使用自己的 Cloudflare 账户建立 D1 数据库，把返回的数据库 ID 填入本地配置；限流绑定的 `namespace_id` 选本账户未占用的值。
3. 应用数据库结构，再部署 Worker：

```sh
npx wrangler d1 create decent-remote-usage
npx wrangler d1 execute decent-remote-usage --remote --file=schema.sql
npx wrangler deploy
```

4. 验证实际 HTTPS 地址的 `/v1/summary`，并先用测试编号核对新增、重复更新和删除。通过后，发布者把 `plugin.tcl` 中 `usage_endpoint` 的默认值换成自己的 `https://服务域名/v1/check-in`，再重新生成安装包和源码包。这样全新安装会自动使用正式地址，不需要每位用户配置。已有配置中的非空地址保持不变；已装过空地址候选的测试设备需单独补上地址。不要向插件分发 Cloudflare 或 GitHub 管理令牌。

示例关闭 Worker 可观测日志。请求按路由限流，不使用 IP 或安装编号作限流键；Cloudflare 的限流按边缘位置生效，不能当作全局硬额度或真实安装证明。

## GitHub 汇总页

在仓库设置中启用 Pages → GitHub Actions。增加仓库变量 `USAGE_SUMMARY_URL`，值为已部署服务的 `https://域名/v1/summary`。运行 `Usage by country` 工作流，之后按日更新。

工作流只读取公开汇总，检查字段、类型和总数，再发布 `statistics/site/`。接口失败或数据不合法时不覆盖已发布页面；变量为空时不运行部署。页面支持中英文，不加载外部字体或分析脚本。包内 `data.json` 是正式接口导出的汇总快照，不是持续更新的在线页面。

参考：[Cloudflare 请求元数据](https://developers.cloudflare.com/workers/runtime-apis/request/)、[D1](https://developers.cloudflare.com/d1/)、[限流绑定](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)、[GitHub Pages 工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)。
