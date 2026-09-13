# 第三方声明

## MaxMind GeoLite2

IP 归属地与 ASN 查询使用 MaxMind 的 GeoLite2 数据库（不随源码分发，由官网服务器定期同步后供应用下载）。

This product includes GeoLite2 data created by MaxMind, available from https://www.maxmind.com.

`Packages/OpenStatsKit/Sources/Metrics/MaxMindDatabase.swift` 按 MaxMind DB 文件格式规范 2.0 自行实现，未使用第三方库。

## flag-icons

`Packages/OpenStatsKit/Sources/OpenStatsUI/Resources/Flags/` 中的国旗 SVG 来自
[lipis/flag-icons](https://github.com/lipis/flag-icons)，MIT License，Copyright (c) 2013 Panayiotis Lipiridis。

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
