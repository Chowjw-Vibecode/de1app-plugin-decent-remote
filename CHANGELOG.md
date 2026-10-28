# Changelog / 更新记录

## 0.3.4 — 2026-10-28

- Add five named favorites to the Current page, using the tablet’s saved order; selecting a shortcut loads the recipe without starting the machine. / 主屏增加五个具名常用曲线按钮，沿用平板顺序，点击加载配方但不启动机器。
- Explain the daily wake schedule with a concrete example, including matching start/end times. / 用具体例子说明每日唤醒和保持唤醒时段，明确两个时间相同的含义。

- Add country-level installation statistics through Cloudflare Workers and D1, with a bilingual GitHub summary page. / 增加 Cloudflare 地区安装统计及 GitHub 中英文汇总页。
- Deduplicate by random installation ID; older requests cannot overwrite a newer country. / 随机安装编号去重，旧请求不覆盖新地区。
- Update in a background thread, only while idle or asleep; no extra UI. A configuration-file option can disable updates. / 仅在待机或休眠时后台更新，不增加界面，可通过配置停用。
- Include the deployed Cloudflare service URL; country totals are available through GitHub Pages. / 写入已部署的 Cloudflare 正式地址，通过 GitHub Pages 展示地区汇总。
- Load the full profile library automatically, preview native basic parameters, and distinguish unsupported types. / 自动读取全部曲线名称和配方，显示原生基本曲线参数并区分未知类型。
- Localize known stage labels without renaming saved data; tolerate near-zero floating-point residue when previewing profiles. / 常见分段名称随界面切换，保留原始文件；预览兼容接近零的浮点误差。

## 0.3.3 — review candidate / 待审候选

- Return to the plugin list after saving an access key successfully; keep invalid or failed saves on the settings page. / 密钥保存成功返回插件列表，输入或写入失败仍留在本页。
- Populate history names and metrics automatically on opening History; failed records remain retryable without hiding other shots. / 打开历史后自动补齐名称和指标，失败记录可重试，不影响其他记录显示。
- Keep the last-shot chart and label consistent after a failed read and a successful retry. / 读取失败与重试成功后，同步恢复上一杯图表和标题。
- Clarify that updates retain the existing key; the default applies only to new installs. / 明确升级保留原密钥，默认值仅适用于全新安装。

- Keep unconfirmed profile changes blocked from Save and Save as, including repeated clicks and page reloads. Resending requires an explicit action. / 曲线发送未确认时，重复保存、另存和刷新页面均保持拦截；仅主动点击才重新发送。
- Preserve custom profile and stage names in lists, zoomed charts and dialogs when switching languages. / 切换语言时，在列表、放大图和弹窗中保留用户名称。
- Improve English wording, confirmation and error messages, empty states and singular/plural labels; show the correct app version. / 改进英文表达、确认与错误提示、空状态、单复数及版本显示。
- Add English/Chinese documentation, screenshot gallery and install/source archives. / 补充中英说明、截图和安装／源码包。
- Make offline test entry points portable; add a GitHub Actions workflow. / 去除测试入口对私人工具路径的依赖，附自动测试工作流。
- No machine-control protocol changes. Not deployed to the tablet or published. / 未改机器控制协议，尚未部署到平板或发布。

## 0.3.2 — locally validated / 本地已验证

- Fix the access-key settings page reopening after exit during idle transitions. Use de1app's native page navigation to update both the visible page and idle destination. / 修复退出密钥页后待机状态变化又弹回的问题。

## 0.3.1 — local build / 本地版本

- Tablet access-key settings, first-install default key and optional browser connection memory. / 平板密钥配置、首次安装默认密钥、可选记住连接。
- Fix the settings-page hide callback and clear stale disconnected status after reconnect. / 修复页面隐藏回调及重连后的残留断线提示。

## 0.3.0 — local build / 本地版本

- Independent browser dashboard, bilingual themes, profile import, editing, history charts and native control API. / 独立网页、中英深浅色、导入与编辑曲线、历史图表和原生控制接口。
