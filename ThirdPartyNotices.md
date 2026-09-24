# 第三方声明

## flag-icons

`Assets/flags-svg/` 中的国旗 SVG（应用内为 `Scripts/render_flags.sh` 渲染的 PNG）来自
[lipis/flag-icons](https://github.com/lipis/flag-icons)，MIT License，Copyright (c) 2013 Panayiotis Lipiridis。

## 登录按钮的品牌标志

`Packages/OpenStatsKit/Sources/OpenStatsUI/Resources/Logos/github.svg` 来自
[primer/octicons](https://github.com/primer/octicons) 的 mark-github，MIT License，Copyright (c) GitHub Inc.；
`google.svg` 是 Google 的品牌标志，仅按其品牌规范用于“使用 Google 登录”按钮。Apple 标志使用系统 SF Symbols 的 `apple.logo`。
GitHub、Google 与 Apple 的名称和标志均为各自公司的商标。

## 运营商标志

`Packages/OpenStatsKit/Sources/OpenStatsUI/Resources/Logos/carrier-*.svg` 是中国电信、中国联通、中国移动的标志，
仅在网络测速里用来标明各列延迟对应的运营商。三家的名称和标志均为各自公司的商标。

## exelban/stats

OpenStats 的以下部分移植自 [exelban/stats](https://github.com/exelban/stats)：

- `Packages/OpenStatsKit/Sources/SMC/SMCConnection.swift`：SMC 参数结构体布局与读写流程
- `Packages/OpenStatsKit/Sources/SMC/FanControl.swift`：Apple Silicon 风扇手动模式解锁流程
- 菜单栏迷你样式的字号与基线参数

```
MIT License

Copyright (c) 2019 Serhiy Mytrovtsiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
