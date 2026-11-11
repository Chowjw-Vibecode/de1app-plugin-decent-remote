# Decent 工具使用地区统计

[English](README.en.md)

按国家／地区汇总 Decent Remote 和「这一杯 · This Cup」的安装数量，可查看全部或单个产品。随机安装编号用于去重，不发送姓名、账户、密钥、曲线或出杯记录。

**Cloudflare Worker 与 D1 已部署，0.3.4 已配置正式服务地址。** [公开汇总页](https://chowjw-vibecode.github.io/usage-stats/)。

服务端支持 v1 旧插件汇总及 v2 分类汇总。版本字段由新版客户端补报，旧记录显示未知版本。

服务：`https://decent-remote-usage.decent-remote-stats.workers.dev`；[地区汇总](https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary)。部署冒烟验证了新增、去重、校验、删除和汇总导出；验证范围见 [VALIDATION.md](../docs/VALIDATION.md)。

## 数据流

`插件随机编号 → Cloudflare Worker → D1 地区记录 → 汇总接口 → GitHub Pages`

- 平板保存随机安装编号、上次尝试及成功时间；成功后七天更新一次，失败后至少隔一天重试。
- D1 保存编号的 SHA-256 摘要、产品分类、国家／地区、最近上报版本、首次及最近更新时间。旧记录和未传分类的旧客户端归入 `decent_remote`；「这一杯」为 `this_cup`。不同产品分别去重，不将同一随机编号跨产品合并。
- GitHub 页面只有地区数量、近 30 天活跃安装数量及汇总时间，没有安装明细。
- 国家／地区由 Cloudflare 请求元数据推定。VPN、重新安装和伪造请求可能影响结果；不是人数统计。应用数据库和日志不保存原始 IP，Cloudflare 会处理请求所需的网络信息。
- 无配置地址不联网。客户端用独立线程，缺少依赖时跳过；不影响本地控制，也不操作咖啡机。配置停用方法见安装包 `docs/USAGE.md`。
- 上述线程和配置方式属于经典 de1app 插件。「这一杯」浏览器客户端发送随机编号、产品分类与当前版本，不携带登录凭据；浏览器存储被清空、换浏览器或更换页面来源可能新增一条安装。两类数据都不是人数或实体设备数。

## 接口

| 方法与路径 | 用途 |
| --- | --- |
| `POST /v1/check-in` | `{"install_id":"32位随机小写十六进制","product":"this_cup"}`；`product` 可省略，默认 `decent_remote`，只允许这两个类别 |
| `DELETE /v1/check-in` | 同一请求体仅删除相应产品内的安装记录；旧客户端省略分类仍只删除 Decent Remote 记录，可重复调用 |
| `GET /v1/summary` | 保持 `schema: 1` 的原字段与含义，仅返回 Decent Remote 地区安装数及近 30 天活跃安装数 |
| `GET /v2/summary` | `schema: 2`，顶层为全部产品合计，增加 `products` 数组，固定包含两个类别（零安装类别也保留） |
| `OPTIONS /v1/check-in` | 浏览器预检，不写库；允许 `POST`、`DELETE` 和 `Content-Type`，不允许携带凭据 |

两个汇总版本的 `countries` 都是 `[{"country":"CN","installations":整数,"active_30d":整数}]`。v2 的每个 `products` 条目含 `product`、`total_installations`、`active_30d`、`countries`、`versions`；顶层同名总数和地区数必须等于分类之和。`generated_at` 和 `scope` 保持原定义，汇总不含安装编号。POST 成功响应仍为 `{"accepted":true,"next_check_in_after_s":604800}`。

所有响应允许匿名跨域访问（`Access-Control-Allow-Origin: *`，不设置 Allow-Credentials），以支持本地浏览器皮肤。国家仅取自 Cloudflare 请求元数据；额外提交国家、IP、设备身份等字段会被拒绝。旧产品编号摘要保持不变，新产品摘要加入产品前缀，分类变更不会串改旧安装。

以服务器收到请求的时间判断新旧。较早请求不能覆盖新地区；同一秒保留已有地区；首次时间取最早值。随机编号也用于删除自己的记录，应留在本地配置，不写进公开日志。

## 本地检查

在源码包根目录运行，需 Node.js 22.13+、Tcl 8.6/Tcllib、Python 3.10+：

```sh
node --test statistics/tests/worker.test.mjs
tclsh8.6 statistics/tests/client.test.tcl
python3 statistics/tests/export.test.py
node --test statistics/tests/site.test.mjs
```

SQL 使用内存 SQLite，客户端用模拟传输，均不连接真实服务。客户端运行时还需要 Tcl Thread、TclCurl 及 de1app 的 `allcerts.pem`。

页面检查使用 Playwright 验证旧项目地址跳转到统一统计页，以及自动跳转不可用时的备用链接，覆盖桌面和手机宽度；目标页面由本地夹具替代，不访问设备或真实统计服务。统计界面与版本表的测试位于 [usage-stats 仓库](https://github.com/Chowjw-Vibecode/usage-stats/tree/main/tests)。

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

### 已有 v1 服务升级分类

在 `statistics/` 中执行，先保留 v1 汇总作对照，随后先迁移旧库，再部署 Worker。`migrations/0001_products.sql` 只适用于已有、尚无 `product` 列的 v1 数据库；全新库使用上方当前 `schema.sql`，不要再对全新库应用这份升级迁移。Wrangler 记录已应用迁移，重跑迁移命令不会重复执行。

```sh
curl --fail --silent --show-error https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary
npx wrangler d1 migrations list decent-remote-usage --remote
npx wrangler d1 migrations apply decent-remote-usage --remote
npx wrangler d1 execute decent-remote-usage --remote --command "SELECT product,COUNT(*) AS installations FROM installations GROUP BY product"
npx wrangler deploy
curl --fail --silent --show-error https://decent-remote-usage.decent-remote-stats.workers.dev/v1/summary
curl --fail --silent --show-error https://decent-remote-usage.decent-remote-stats.workers.dev/v2/summary
curl --silent --show-error --include --request OPTIONS --header 'Origin: http://localhost:8080' --header 'Access-Control-Request-Method: POST' --header 'Access-Control-Request-Headers: content-type' https://decent-remote-usage.decent-remote-stats.workers.dev/v1/check-in
```

核对迁移前后旧类安装总数一致、v2 的 `decent_remote` 等于 v1、`this_cup` 在没有新上报时为零，且预检为 204。不要对外输出安装明细。通过后再发布统计页面与浏览器客户端；页面导出失败时保留线上旧页面。若已收到「这一杯」记录，不能直接恢复不识别分类的旧 Worker，否则旧汇总会混入新类别；回退版本须保留 v1 的产品筛选及新增列，不删除历史记录或回滚整库。

## GitHub 汇总页

在仓库设置中启用 Pages → GitHub Actions。仓库变量 `USAGE_SUMMARY_URL` 可保持原 `https://域名/v1/summary`，也可设置为 `/v2/summary`；工作流的 `--products` 会明确读取同一服务的 `/v2/summary` 并要求分类汇总。运行 `Usage by country` 工作流，之后按日更新。

工作流只读取公开汇总，检查字段、类型、分类及地区总数，再发布 `statistics/site/`。接口失败或数据不合法时不覆盖已发布页面；变量为空时不运行部署。页面支持中英文和「全部／Decent Remote／这一杯」分类，不加载外部字体或分析脚本。包内 `data.json` 保留已有正式汇总快照；遇到旧版快照时页面明确说明仅包含 Decent Remote，「这一杯」显示尚未上线，不把缺失数据显示成零。

参考：[Cloudflare 请求元数据](https://developers.cloudflare.com/workers/runtime-apis/request/)、[D1](https://developers.cloudflare.com/d1/)、[限流绑定](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)、[GitHub Pages 工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)。

`versions` 按产品分别汇总，条目为 `{version: 字符串或null, installations: 整数, active_30d: 整数}`；null表示未知。同一安装升级只更新版本，不新增计数；版本按服务端最后收到的有效上报更新，支持降级。缺版本不擦除已知值。
