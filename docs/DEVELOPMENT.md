# Development / 开发

The plugin runs in de1app. Node and Python are only used on your development computer for tests and packaging; they are not required on the tablet.

插件在 de1app 内运行。Node、Python 仅用于电脑上的测试与打包，平板无需安装。

## Offline tests / 离线测试

Install Tcl **8.6**, Tcllib, Python **3.10+**, Node **22.13+**, then:

```sh
npm ci
npx playwright install chromium
python3 tests/run.py --browser
node --test statistics/tests/worker.test.mjs
tclsh8.6 statistics/tests/client.test.tcl
python3 statistics/tests/export.test.py
```

On Linux, Playwright may also need its documented system dependencies (`npx playwright install --with-deps chromium`). If the Tcl executable or Tcllib is not found automatically:

```sh
python3 tests/run.py --browser --tcl86 /path/to/tclsh8.6 --tcllib /path/to/tcllib
```

The runner passes the chosen runtime to every suite. Browser requests are intercepted; HTTP integration binds only to `127.0.0.1`. All machine methods are mocked. Tests do not connect to your tablet.

测试使用指定的 Tcl 环境。浏览器请求全部拦截；HTTP 测试只监听本机回环地址；机器方法均模拟，不连接平板。

## Documentation images / 文档截图

```sh
REMOTE_SCREENSHOT_DIR=docs/images node tests/dashboard.test.cjs
```

Screenshot mode uses denser synthetic chart data, captures the actual page in both languages/themes, then exits. It does not count as a full regression run. / 截图模式使用更密集的合成采样，截取正式界面后退出，不能当作完整回归。

## Build / 打包

```sh
python3 tools/build_release.py
```

Outputs under `dist/`:

- `decent_remote-vVERSION.zip`: install archive, one `decent_remote/` folder. / 安装包。
- `decent-remote-vVERSION-source.zip`: public repository snapshot, including tests and CI. / 待上传 GitHub 的源码快照。

The builder uses an explicit file allowlist and refuses symlinks. It never copies settings, device logs, local design material or the research database. Both archives include the README screenshots; the install archive omits development tests and Node packages. The source archive can build the same install archive independently.

构建器只复制明确列出的文件，不接受符号链接；不带配置、设备日志、设计原稿或研究数据库。安装包不含开发测试与 Node 包，源码包可独立生成相同安装包。

The included GitHub Actions workflow runs offline checks and uploads build artifacts when the repository is later published. It does not publish a release, deploy files or connect to a device. / 工作流只做离线检查和构建，不自动发布、部署或操作设备。

## Statistics service / 统计服务

The source bundle includes `statistics/` and a separate Pages workflow. It stays inactive until the repository variable `USAGE_SUMMARY_URL` is set and Pages is enabled. See `statistics/README.en.md` / `statistics/README.md` in the source bundle. No collector or Pages deployment occurs when building a release archive. / 构建发布包不会部署统计服务或汇总页。
