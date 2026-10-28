# Using the API from an AI agent / AI Agent 接入

[API reference](API.md) · [中文接口](../API.md)

Decent Remote exposes an HTTP API. It does not ship an MCP server, agent account or cloud relay. Use an HTTP-capable agent on the same trusted network as the tablet.

Decent Remote 提供 HTTP API，不附带 MCP 服务、Agent 账号或云端转发。让具备 HTTP 能力的 Agent 在平板可达的可信网络内调用即可。

## Read-only first / 先读状态

Set `DECENT_URL` and `DECENT_KEY` in your local environment. Keep the key out of prompts and logs. This example uses only GET requests:

在本地环境配置地址和密钥，不写进提示词或日志。以下示例仅查询：

```python
import json
import os
from urllib.request import Request, urlopen

base = os.environ["DECENT_URL"].rstrip("/")
key = os.environ["DECENT_KEY"]
for path in ("/api/v1/status", "/api/v1/profile"):
    request = Request(base + path, headers={"Authorization": "Bearer " + key})
    with urlopen(request, timeout=5) as response:
        print(json.dumps(json.load(response), ensure_ascii=False, indent=2))
```

## Before changing anything / 修改前

1. Read the current profile and machine state. Do not fill in missing values from an old shot. / 读取当前状态，不用历史配方补猜。
2. Keep changes within the user's request. Loading, applying, saving and starting are distinct actions. / 按用户授权区分载入、应用、保存和启动。
3. Send a unique request ID for a write. Wait for its result before another profile write. / 写操作带唯一请求编号，前一笔结束再发下一笔曲线修改。
4. Query the request result if the connection drops. A missing response does not prove that nothing happened. / 连接中断先查结果，不把无响应视作未执行。
5. Read back the affected values. Separate app state and profile-frame confirmation from actual flow, temperature and cup weight. / 修改后读回，区分 App 数据、帧确认与实际出水表现。

Remote starts are off by default. The integration must not silently enable them or bypass the machine's native controls. / 远程启动默认关闭，接入方不得静默开启或绕过原生控制。
