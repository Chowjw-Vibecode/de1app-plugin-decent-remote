# Validation scope / 验证范围

## 0.3.4 home shortcuts and wake schedule / 主屏常用与每日唤醒

The updated dashboard passed **9 focused development checks**. These cover favorite names and ordering, loading a recipe without starting the machine, unsaved edits, duplicate clicks, busy/offline states, favorites management, stale favorite selection, responsive layout and the bilingual wake-schedule explanation. Requests were intercepted using synthetic fixtures.

更新后的网页通过 **9 项定向开发自检**，覆盖常用名称与顺序、载入配方而不启动机器、未保存修改、连点、忙碌与断线、常用管理、失效常用选择、响应式布局及中英文唤醒说明。请求使用合成接口拦截。

Independent targeted regression passed for favorite-list changes and failed or in-flight refreshes while a discard confirmation is open. Such cases retain the draft and do not load an outdated selection. It also checks error messages in both languages and layouts from narrow phones to landscape tablets. Earlier full-library and backend checks below describe their original coverage, not a repeated full run for this UI change.

独立定向回归已通过，覆盖放弃修改确认框打开期间，常用列表变化、刷新失败或刷新仍在途的情况；这些情况保留草稿，不载入失效选择。另核对双语错误提示及窄屏到横屏平板的布局。下方整库及后台测试保留其原验证范围，不表示本次界面修改后重复全测。

## 0.3.4 statistics candidate / 统计候选

The statistics implementation passed focused independent offline checks. The Cloudflare Worker and D1 database are now deployed. Fourteen deployment checks passed for creation, deduplication, validation, deletion and country totals; synthetic records were removed. The production summary exporter also ran successfully. The checks in this paragraph were completed before GitHub publication. The native tablet client subsequently succeeded, and its record was independently matched in D1.

统计实现已通过独立离线定向检查，Cloudflare Worker 与 D1 现已部署。新增、去重、校验、删除及地区总量等 14 项部署检查通过，合成记录已清除；汇总导出器已读取正式服务。本段检查完成于 GitHub 发布前，平板原生客户端随后成功，且已在 D1 独立匹配对应记录。

| Area / 范围 | Evidence / 证据 |
|---|---|
| Client / 客户端 | 11 project checks and 11 independent Thread/transport checks passed; TclCurl was simulated / 项目 11 项、独立线程与传输 11 项通过，TclCurl 使用模拟库 |
| Export / 汇总导出 | 9 project checks, 16 independent boundary checks and 7 fix-specific checks passed / 项目 9 项、独立边界 16 项、修复边界 7 项通过 |
| Plugin lifecycle / 插件生命周期 | 14 checks passed, including the production default, explicit empty endpoint, timer shutdown and startup-error isolation / 14 项通过，覆盖正式默认地址、显式空地址、停止定时器及统计异常隔离 |
| Summary page / 汇总页 | 12 isolated browser scenarios across two widths, with English/Chinese switching; synthetic data only / 两尺寸及中英文切换，共 12 组隔离浏览器场景，仅用合成数据 |
| Worker / 统计服务 | The unchanged backend retains its prior passing checks, including deduplication and out-of-order updates / 未变动后台沿用此前已通过的去重及乱序更新检查 |
| Pages workflow / 页面发布流程 | Export CLI exercised with simulated HTTP; job guards and dependencies inspected. No live GitHub Actions run / 模拟 HTTP 执行实际导出命令，检查任务条件与依赖；未在线执行 Actions |

The repaired cases cover the classic state adapter, interrupted writes to a `.tmp` output, non-integer schema values, and invalid date messages. Statistics do not control the coffee machine. The current candidate also repairs full-library loading and native basic-profile previews, as described below.

已修复并复测经典状态适配器、`.tmp` 目标中断写入、非整数版本字段及异常日期提示。统计不控制咖啡机；当前候选另外修复整库加载和基本曲线预览，验证另列。

## 0.3.4 profile-library verification / 曲线库验证

The earlier profile-library dashboard passed **66 isolated browser checks**, including the two native preinfusion labels, active basic-profile temperature fields and near-zero number boundaries. Requests were intercepted; no machine traffic was sent by this suite.

此前曲线库网页候选通过 **66 项隔离浏览器检查**，包含两个原生预浸名称、基本曲线有效温度字段及接近零的数值边界。此套件拦截网络请求，没有连接机器。

On the installed tablet, an independent tester opened all **123 profiles in English and Chinese: 246 previews**. List titles before and after selection agreed with the source titles. All 96 advanced profiles had the expected stage count in both languages; all 27 basic profiles displayed their parameters without a misleading “0 stages” label. The cleaning profile with near-zero floating-point residue could also be opened.

测试专员在已安装的平板网页逐条点击 **123 条曲线，中英文共 246 次预览**。点击前后名称与来源一致；96 条高级曲线的双语阶段数量一致，27 条基本曲线均显示基本参数，不再标成“0 段”。含接近零浮点误差的清洗曲线也可预览。

For the current basic profile, all 12 displayed values matched the API in each language. The other 26 basic profiles contributed 570 displayed values checked against saved source samples; those comparisons do not prove the files were unchanged between sampling times. Two initial mismatches were test errors caused by including internal fields that the UI does not display. The test was corrected. A missing native-stage translation was identified separately and corrected.

当前基本曲线每种语言的 12 个展示数值均与同次接口读回一致。其余 26 条基本曲线的 570 个双语展示数值与已保存来源样本一致；这不证明两次取样间文件完全未变。最初两项数值差异是测试把未展示的内部字段计入比较造成的误报，已纠正。另有一个原生阶段名称漏译，已独立定位并修正。

The native basic-profile GET contract passed 17 focused synthetic checks, including invalid numbers, equivalent zero values, temperature flags and absence of conversion support. It uses de1app's native conversion on a local copy; it does not load a profile or send it to the machine. Private source samples and native conversion copies are not distributed in these packages.

基本曲线只读接口通过 17 项定向合成检查，覆盖异常数值、等价零值、温度开关及转换支持缺失。预览在局部副本上调用 de1app 原生转换，不载入曲线、不发送机器命令。私人样本和本机原生源码副本不进入发布包。

The installed-tablet checks issued only reads. The current profile, recipe and modification state were preserved; the machine remained idle with zero flow. This verifies the profile-preview path, not brewing performance.

实机逐项核对仅执行读取，当前曲线、配方和修改状态保持不变，机器仍待机、零流量。此结论针对曲线预览，不代表实际冲煮性能已验证。

## 0.3.3 baseline / 已有基线

Version 0.3.3 is a local release candidate. It improves interface localization and preserves user-defined names. The browser now also keeps unconfirmed profile changes blocked from Save and Save as, across repeated attempts and page reloads; only an explicit Resend profile action sends again. The underlying machine-control protocol is unchanged. The follow-up UI build was installed on one tablet and passed the focused checks described below.

0.3.3 为本地待审候选，改进中英文界面并保留用户名称。网页新增独立的发送确认状态：未确认时重复保存、另存和刷新页面均保持拦截；仅主动点击“重新发送”才重发。底层机器控制协议不变；补充界面修复已安装到一台平板并通过下方定向验证。

The earlier localization candidate passed independent offline regression: **58 browser checks**, plus targeted checks for repeated saves, response loss, page reloads, disabled session storage, and external changes during load/restore/save-as. Tests used the actual dashboard with intercepted requests and simulated device confirmations. Both packages were rebuilt independently and matched the supplied candidates.

此前本地化候选已通过独立离线复测：**58 项浏览器检查**，另针对重复保存、响应丢失、刷新、页签存储禁用及载入／恢复／另存期间的外部修改进行了检查。使用正式网页、拦截网络请求和模拟设备确认；两份包也完成独立重建核对。

The prior Tcl and HTTP implementation passed **330 unit/integration checks and 41 local HTTP requests** in an earlier candidate. Those baseline results remain applicable to unchanged paths; the later access-key Save change has separate focused checks below. They are not a claim of a new physical-device test. Documentation was finalized after the browser review. GitHub Actions has not run on GitHub.

此前候选的 Tcl 与 HTTP 实现通过 **330 项单元／集成检查和 41 次本地 HTTP 请求**；未改动路径保留该基线，后续密钥页保存修改单独定向复测，见下方。这不表示进行了新的实机测试。浏览器复测后补充了最终操作说明。GitHub Actions 尚未在线运行。

A fresh page or explicit profile load/restore does not inherit a device confirmation. Saving unchanged current values requires an explicit resend and its matching confirmation. The initial save of a newly edited draft can apply the draft and wait for confirmation only when this page has no unresolved transfer; otherwise an explicit resend is required, even after further edits. / 刷新、新页面、载入或恢复都不继承设备确认；保存未改动的现值前需要明确重发并取得对应确认。仅当本页没有待处理的未确认发送时，新草稿首次保存可自动应用并等待确认；否则即使再次编辑也需明确重发。

## Follow-up UI regression / 界面补充回归

The follow-up dashboard passed **63 public browser checks**, **12 focused checks replaying 79 real shot records**, and **8 Chinese/English, dark/light, two-viewport checks**. History rows load their names and metrics without individual clicks. Failed records can be retried, and the latest-shot chart and label recover together. Only synthetic fixtures are included in the public source archive.

补充网页回归已通过 **63 项公开浏览器检查、79 条真实历史响应的 12 项定向回放，以及中英文、深浅色、两种尺寸共 8 组界面检查**。历史名称和指标无需逐条点击；读取失败可以重试，上一杯图表和标签同步恢复。公开源码包仅含合成测试数据。

The access-key Save change passed **23 existing checks and 5 independent checks**. A successful save returns through the native page route; invalid input and failed writes stay on the settings page. These checks simulate page routing and do not substitute for physical tablet verification.

密钥页保存返回修改通过 **23 项现有检查和 5 项独立检查**。成功保存通过原生页面路由返回，输入无效或写入失败则留在设置页。这些检查使用模拟页面，不能代替平板验证。

## Prior device evidence / 既有实机证据

- classic de1app 1.46.1.1 with Streamline, one Android tablet. / 单台 Android 平板。
- 0.3.1: status, profile and reversible settings paths, compatibility endpoints, browser reads and start-lock/native-control guards were checked. / 已检查状态、曲线、可逆设置、兼容接口及启动拦截。
- 0.3.2: cancel with an unsaved key draft, save the original key, repeat entry/exit, two natural idle transitions, sleep/wake and return to the home page passed. 22 restoration checks passed. / 密钥页定向回归及 22 项恢复检查通过。
- A follow-up weight check agreed between the user's scale display, tablet UI and Remote response. Older Bluetooth log errors were also present before 0.3.2; their precise cause remains unresolved. They are not established as a regression in this plugin. / 用户秤屏、平板与接口读数核对一致；既有蓝牙错误根因尚未确定，不能归为本次插件回归。

## 0.3.3 follow-up tablet checks / 补充平板验证

On one classic de1app 1.46.1.1 / Streamline tablet, Save returned to the plugin list and two controlled Sleep-to-Idle cycles did not reopen the key page. A fresh browser session loaded all 79 available history records without individual clicks; names and available numeric fields matched their source records. Current-profile and preview names stayed correct across language changes and page refreshes. Fifteen final checks passed, including retained recipe values, unchanged shot count, zero flow, preserved plugin configuration and installed-file readback.

在一台 classic de1app 1.46.1.1 / Streamline 平板上，保存后返回插件列表，两次受控休眠→待机均未重新弹出密钥页。新浏览器会话中的 79 条历史无需逐条点击，名称及可用数值与来源一致；当前和预览名称在语言切换、刷新后保持正确。最终 15 项核对通过，包括配方保留、出杯计数不变、零流量、插件配置保留及安装文件读回。

This was a focused UI verification. No brewing, flushing, hot-water, steam or grinder start was executed. It did not repeat every native setting or reproduce natural Idle/UserNotPresent transitions. Private records and screenshots are excluded from the public packages.

这是定向界面验证，未启动萃取、冲洗、热水、蒸汽或磨豆。没有逐项重测所有原生设置，也未复现自然 Idle/UserNotPresent 子状态变化。私人记录和截图不进入公开包。

## Not covered / 未覆盖

- Other de1app releases, skins, tablets or operating systems. / 其他版本、皮肤、设备与系统。
- Physical espresso, flush, hot-water, steam or grinder starts. Native restrictions were not bypassed. / 未实机执行各类出水、蒸汽或磨豆启动，不绕过原生限制。
- Real network loss during a physical operation, loaded-device faults or long-term operation. / 实际运行中的断网、负载故障和长期稳定性。
- A new firmware version or factory flow calibration. / 未升级固件或修改官方流量校准。

Private device logs, credentials, network identities and personal shot records are deliberately excluded. The repository contains synthetic test data and a limited profile fixture. / 不公开私有日志、密钥、网络身份或个人出杯记录，仅提供合成测试数据与有限的曲线样例。
