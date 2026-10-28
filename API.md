# Decent Remote 0.3.5 API

本文件描述 0.3.5 服务和网页接口。参数调整、状态读取与停止操作沿用 de1app 原生控制；远程启动接口已停用。

密钥在平板插件设置页修改，不提供远程改密钥端点。新安装默认 `admin1234`，现有密钥优先保留；保存新密钥后立即用于鉴权，旧密钥返回 401（旧接口返回 403）。允许 8–128 位可见 ASCII、无空白。网页仅在用户勾选“记住连接”且鉴权成功后保存到浏览器本地存储。

## 请求、结果和鉴权

`/api/v1/` 使用 `Authorization: Bearer <token>`，不接受查询参数鉴权。所有非 GET 请求带唯一 `X-Request-ID`（8–80位字母、数字、`_`、`-`）。无参数 POST 发送 `{}`；选择文件的 PUT 不带正文。正文使用 UTF-8；URL 文件名按 UTF-8 编码。

当前传输使用 GET、POST、无正文 PUT。更新参数使用 POST，不使用 PATCH。未知字段会被拒绝。JSON 数值与布尔值应使用对应类型，不传数组代替单个值。重复请求 ID 返回409，即使第一次尝试失败；更换 ID 不等于可以安全重试。

常见错误：400请求格式错误、401新接口鉴权失败、403启动被禁用或旧接口鉴权失败、404不存在、409忙碌/冲突/重复请求、422参数无效、501功能或依赖不可用、502发送/保存结果未知。应用可能已更新但设备发送或保存失败时，不承诺回滚。

GET `/api/v1/requests/{request_id}` 返回当前进程记录，包括 `in_flight`（当前曲线请求是否仍在发送）、`phase`、`accepted`、`app_applied`、`device_confirmed`、`confirmation_scope`、HTTP状态及时间。可能的阶段包括 `processing`、`accepted_unconfirmed`、`app_applied`、`frames_queued`、`frames_confirmed`、`frames_unconfirmed`、`unconfirmed_timeout`、`superseded`、`rejected`、`outcome_unknown`。

`confirmation_scope=profile_frames_only` 只表示对应的原生曲线帧确认范围。它不确认杯重、实际流量、温度稳定或物理动作完成。多个发送交叠而无法确定归属时，不授予确定确认。超时表示尚未观察到确认，不表示硬件一定失败。重启后旧记录返回404。

曲线修改、载入、恢复、保存与另存共用单个在途门闩。前一请求未结束时，新的曲线写入在修改设置之前返回409；没有后台积压队列。30秒未确认会标记超时，若原生发送仍挂起则继续阻止新写入。读请求、停止、纯文件导入不受此限制。旧路径与新路径共享这一限制。

## 端点总表

|方法|路径|用途|
|---|---|---|
|GET|`/api/v1/status`|连接、状态、温度、流量、压力、秤与配方缓存|
|GET / POST|`/api/v1/recipe`|粉量、杯重目标与全局温度临时调整|
|GET / POST|`/api/v1/profile`|当前完整曲线、分段及临时修改|
|POST|`/api/v1/profile/restore`|重载当前曲线文件|
|POST|`/api/v1/profile/save`|原生保存当前曲线并读回|
|POST|`/api/v1/profile/save-as`|另存为新的 Tcl/JSON 曲线|
|GET / POST|`/api/v1/favorites`|Streamline常用曲线位置|
|GET / POST|`/api/v1/shortcuts`|Streamline粉量/杯重及温度快捷值|
|GET / POST|`/api/v1/settings`|预热、自动休眠、亮度|
|GET / POST|`/api/v1/controls`|冲洗、热水与蒸汽参数|
|GET / POST|`/api/v1/scale`|秤状态与停止策略|
|POST|`/api/v1/scale/tare`|原生秤清零|
|GET / POST|`/api/v1/scheduler`|定时唤醒、保持唤醒区间|
|GET / POST|`/api/v1/charging`|智能充电与机器USB|
|GET / POST|`/api/v1/flow-compensation`|已有补偿插件的只读详情与配置开关|
|GET|`/api/v1/plugins`|相关插件的加载、启用与HDS状态|
|GET|`/api/v1/profiles`|Tcl曲线文件列表|
|POST|`/api/v1/profiles/import`|校验或导入Tcl / v2 JSON；不选择曲线|
|GET / PUT|`/api/v1/profiles/{name.tcl}`|下载/选择曲线|
|GET|`/api/v1/shots`、`/api/v1/shots/{name.shot}`|原始历史列表/文件|
|GET|`/api/v1/shots/json`、`/api/v1/shots/json/{name.json}`|JSON历史列表/文件|
|GET|`/api/v1/requests/{request_id}`|执行结果记录|
|POST|`/api/v1/machine/{wake,sleep,stop}`|原生唤醒、休眠、停止|
|POST|`/api/v1/machine/{espresso,flush,steam,hotwater}`|已停用，返回403 start_disabled|
|POST|`/api/v1/grinder/{start,stop}`|已有小方插件的可选兼容桥，启动已停用|

参数修改通常要求咖啡机已连接且处于 Idle 或 Sleep；设备运行中拒绝编辑。萃取、冲洗、热水、蒸汽及磨豆启动接口统一返回 `403 start_disabled`。不再提供远程启动配置项或按钮；停止、唤醒和休眠仍可用。

## 配方与曲线

`POST /api/v1/recipe` 接受任意非空组合：

|字段|单位与范围|
|---|---|
|`dose_g`|粉量0.1–30 g|
|`yield_g`|杯重目标0–2000 g；0按原生语义处理|
|`temperature_c`|0–105°C；相对平移各段温度，保留温差，超界拒绝|

这是应用内临时调整，不覆盖源曲线。杯重目标通过原生 Streamline 方法同步；它不代表机器计量的进水体积。

`GET /api/v1/profile` 另含 `editable_steps`、`steps`、`target_volume_ml`、`volume_count_start`、`notes`、`dirty`。基本曲线另返回只读的 `basic_parameters` 和 `display_steps`。`display_steps_readback=native_conversion` 表示阶段由原生转换函数在设置副本上生成，不会发送给机器；`unavailable`、`invalid_parameters`、`empty` 分别表示无法生成、参数无效、各段时长为零。基本曲线的 `steps` 仍为空、`editable_steps=false`，不能将这两个字段解释为曲线没有内容。

选择曲线的 PUT 响应包含 `current_profile`，用于把本次选择的参数快照与请求回执对应；它不代替设备确认。

`POST /api/v1/profile` 可提交配方字段及以下字段：

- `steps`：高级曲线的完整分段数组，1–20段；开启原生额外预浸暂停时最多19段。基本曲线不接受分段编辑。
- `target_volume_ml`：机器计量的目标体积，0–2000 mL；不同于秤上的杯重。
- `volume_count_start`：高级曲线体积计数起点，整数0至分段数，沿用原生语义。
- `notes`：说明文字，最长10000字符。

分段必需字段为 `pump`（`pressure`或`flow`）、`sensor`（`coffee`或`water`）、`transition`（`fast`或`smooth`）、`temperature`、`seconds`，以及与 `pump` 对应的 `pressure` 或 `flow`。可选 `name`、`popup`、`volume`、`weight`、`max_flow_or_pressure`、`max_flow_or_pressure_range`、`exit_if`、`exit_type` 和退出阈值。

温度0–105°C，时长0–127秒，压力0–12 bar，流量0–12 mL/s，分段体积0–1023 mL，分段重量0–2000 g。退出类型为 `pressure_under`、`pressure_over`、`flow_under`、`flow_over`；启用时必须提交相应的 `exit_*` 阈值。完整分段与 `temperature_c` 同时提交时，全局温度必须等于首段温度。

`coffee`、`water` 是 de1app 的不同控温探头模式，不可互换；设定温度不等于粉饼内部实测温度。流量指令、机器报告流量、秤测重量变化和最终杯重也不是同一量。

恢复、保存与另存是三个独立动作：

- `POST /profile/restore {}`：重新选择当前文件，丢弃未保存的当前修改；走原生加载、皮肤同步及设置保存。
- `POST /profile/save {}`：保存当前曲线。只读原版返回409，应另存。
- `POST /profile/save-as {"filename":"my-profile.tcl","title":"My profile"}`：另存并切换当前身份；目标 Tcl 或 JSON 已存在则拒绝覆盖。

以上短路径均以 `/api/v1` 为前缀。保存走原生 `save_profile`，核对 Tcl与JSON文件。两文件不是一次原子写入；`save_unknown` 时先读取文件核实，不能直接重试。带可执行 `advanced_shot_tcl` 的曲线不能通过远程编辑或选择执行。

## 本地文件导入

`POST /api/v1/profiles/import` 接受 `filename`、`content`、`format`（`tcl` / `json`），以及可选 `dry_run` 和 `overwrite`（均默认 false）。文件名限定为曲线目录内的单个文件；JSON 转换为 Tcl 参数表。

`dry_run=true` 只校验，不落文件；默认同名409。返回 `filename/title/format/saved/readback`。导入后不改变当前曲线、不发送蓝牙、不启动机器。网页先提交原始内容进行校验，再展示预览；不会通过重新序列化 JSON 掩盖重复字段。

Tcl 只接受参数数据列表，不执行脚本。JSON 支持 de1app v2 高级曲线；未知字段、重复字段、非空临时变更字段及不可表示的语义被拒绝。未提供的粉量/液重不自行补默认值。旧 `/api/profile` 上传路径的同名覆盖语义保持兼容。

## 常用位置与快捷值

`POST /api/v1/favorites`：`{"slots":[{"slot":1,"profile":"my-profile"}]}`。位置1–5，`profile`为不含`.tcl`的文件名；空字符串清空位置。不能重复位置，也不能产生Streamline不支持的重复曲线或重名按钮。

`POST /api/v1/shortcuts`：

```json
{"dose_yield":[{"slot":1,"dose_g":18,"yield_g":36}],"temperatures":[{"slot":1,"temperature_c":92}]}
```

两组各1–4号位置，可只提交其中一组。更新这些位置会保存设置，不等于选择该曲线或启动制作。依赖Streamline原生设置与刷新方法。

## 预热、休眠、亮度

`/api/v1/settings`：

|字段|范围|
|---|---|
|`preheat_phase1_flow_ml_s`|0.5–6 mL/s|
|`preheat_phase2_flow_ml_s`|0.5–8 mL/s|
|`preheat_timeout_s`|1–30秒|
|`idle_temperature_c`|0–99°C，0.5°C步长|
|`sleep_timeout_minutes`|0–480整数分钟；0关闭自动休眠|
|`awake_brightness`、`sleep_brightness`|0–100整数百分比|

预热流量和超时精度为0.1。内部单位由适配器转换。原生预热设置方法会一起重发已有冲洗、热水、蒸汽参数；不修改官方流量校准倍率。

## 冲洗、热水、蒸汽

`/api/v1/controls`：

|字段|含义与范围|
|---|---|
|`flush_flow_ml_s`|1–10 mL/s，0.1步长|
|`flush_timeout_s`|3–120秒，0.1步长|
|`hotwater_flow_ml_s`|1–10 mL/s，0.1步长|
|`hotwater_temperature_c`|0–100整数°C|
|`hotwater_target`|3–255整数；单位看返回字段|
|`hotwater_timeout_s`|1–255整数秒|
|`water_stop_on_scale`|是否按秤重停止热水|
|`steam_enabled`|原生`steam_disabled`的反向开关|
|`steam_flow_ml_s`|0.4–2.5 mL/s，0.01步长；内部乘100|
|`steam_temperature_c`|135–170整数°C|
|`steam_timeout_s`|0–255整数秒；0在固件打包中实际使用255秒|

热水返回 `hotwater_target_unit`、`hotwater_stop_mode`、`firmware_hotwater_volume_ml`、`target_effective` 和提示。秤连接且称重停止开启时，目标是g阈值，固件体积上限设为250 mL；秤连接但关闭称重停止时，原生代码仍使用250 mL，返回 `target_effective=false`，不能认为所设目标体积会生效。

这些POST设置参数，不开始出水。原生蒸汽/热水打包可能连同已有冲洗、蒸汽高流量启动等设置一起发送。

## 秤、定时与充电

`/api/v1/scale` 只读字段包括 `connected`、`scale_type`、`weight_g`、`flow_g_s`、`autotare_states`。自动归零状态列表不可写。可写字段：`require_scale`、`keep_scale_on`、`stop_before_s`（−1至1.5秒，0.01步长）。这些设置不会立即清零；清零使用独立 `/scale/tare`。

`/api/v1/scheduler` 可写 `enabled`、`wake_time`、`awake_until`，时间格式为24小时制 `HH:MM`，使用平板本地时间。结束不得早于开始；相等表示无强制保持唤醒区间。`awake_until`不是定时休眠动作，而是原生“保持唤醒”区间终点。返回 `awake_interval_enabled` 表示区间被配置启用，不代表当前时刻正在区间内；`next_wake_at`是原生计算的Unix秒，禁用时为空。保存会注册未来唤醒计时，不直接调用唤醒/休眠函数。

`/api/v1/charging` 可写 `smart_charging_mode`（`off`、`on`、`night`）和 `machine_usb_enabled`。模式是三选一，不是布尔值。修改模式会立即调用原生充电策略；同次显式USB请求在策略之后执行。周期策略之后仍可能覆盖手动USB状态，即使模式是`off`；`usb_override_temporary=true`明确此限制。

## 可选流量补偿

`/api/v1/flow-compensation` 只允许写 `{"enabled":true}`或`false`。依赖原 `flow_lut` 插件实际加载且启用；未加载时GET返回 `available=false`，写入返回501。不开启新补偿范围，不改表、倍率或校准。

详情包括目标身份、`map_id`、`current_profile_match`、`last_state`、`last_message`、`changes`（`target/command/estimate/stage`）、`ack`、`last_profile`、`updated`、`fallback_reason`。`current_profile_match`仅比较文件和标题，不证明全部参数符合适用条件。`ack_scope=last_published_send`说明ACK属于插件最后发布的发送记录，不能归为当前修改；缺失ACK保持空值。估计流量不是实际出水测量。

## 旧接口兼容

旧路径接受 `?auth=<token>` 或Bearer请求头，允许 `download=true` 和末尾斜杠。旧客户端不强制请求ID；提供后会去重。建议新客户端用v1。

|方法|路径|语义|
|---|---|---|
|GET|`/`、`/api/help`|网页/机器可读接口摘要|
|GET / POST|`/api/status`|简单状态/`active`唤醒或休眠|
|GET|`/api/status/details`|原详细字段；Espresso状态含七组采样数组|
|GET / POST|`/api/profile`|列出/上传Tcl参数表；上传同名覆盖|
|GET / PUT|`/api/profile/{name.tcl}`|下载/选择|
|GET|`/api/shot`、`/api/shot/{name.shot}`|原始历史|
|GET / PUT|`/api/v2/shot/{timestamp}`|JSON历史/DYE“作为下一杯”|
|GET|`/api/v2/shots`|SDB摘要；依赖未启用返回501|
|GET|`/api/flush`|刷日志缓冲，**不是冲洗出水**|

上传正文是UTF-8 Tcl数据列表，`filename`请求头指定`.tcl`文件名，中文文件名可URL编码。路径越界、符号链接、可执行曲线脚本和曲线以外的设置会被拒绝。DYE/SDB均沿用原插件；缺失不复制数据库、不猜历史字段。小方旧桥只调用已有控制链，未安装时返回501，新网页不包含该控件。
