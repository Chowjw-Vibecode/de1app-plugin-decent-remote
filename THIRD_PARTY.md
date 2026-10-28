# Sources and third-party components / 来源与第三方组件

## Project code / 项目代码

Decent Remote's dashboard and service are maintained in this project. The release distributes project code under GPL-3.0-only; see [LICENSE](LICENSE). It uses de1app's native control functions rather than shipping a replacement machine-control implementation.

网页与服务在本项目中实现和维护；本包对项目代码采用 GPL-3.0-only。机器操作调用 de1app 原生方法，不附带完整 App 或替代固件。

## Runtime dependencies / 运行依赖

- **de1app:** [official repository](https://github.com/decentespresso/de1app), [GPLv3 license](https://github.com/decentespresso/de1app/blob/main/LICENSE). The tested runtime is classic 1.46.1.1. The complete App is not included in this package. / 本包不包含完整 App。
- **Tcl/Tcllib and wibble:** supplied by the tested App. wibble is by Andy Goth, Copyright 2009–2014, under the [Tcl/Tk license](https://www.tcl-lang.org/software/tcltk/license.html). Production uses the App's installed copy. / 生产环境使用 App 内置组件。

## Source-only test material / 仅源码包中的测试材料

- `tests/vendor/wibble.tcl`: wibble 0.4, Andy Goth. Original copyright and license header preserved; accompanying license text is in `tests/vendor/TCL-TK-LICENSE.txt`. Used only by loopback HTTP tests. / 保留原版权声明，仅供本地 HTTP 测试。
- `tests/fixtures/filter3.tcl`: a saved Decent Filter3 profile used as parser/import test data. Original `author Decent` retained; source project linked above. No test selects or runs it on hardware. / 仅作解析和导入样例，不运行实机。
- Playwright: test dependency from npm, Apache-2.0. Browser packages and Node modules are not bundled. / 仅开发依赖，不打包浏览器或 Node 模块。

Chart.js and mini.css are not used by the current dashboard and are not included in either archive. / 当前网页不使用这两个旧组件，发布包不携带它们。

## Interface reference / 接口参考

Legacy compatibility paths and field names were checked against Yannick Dietler's [Advanced REST API](https://github.com/randomcoffeesnob/decent-advanced-rest-api), reference commit `f6752e674be08eeb4f970b4122f661ab0c605151`. This is an interface-compatibility reference. Its plugin and webpage are not bundled, and it is not required at runtime.

此处记录旧接口路径与字段的参考来源，用于解释兼容行为；不把接口兼容写成代码继承。本包不附带或运行该插件及其网页。
