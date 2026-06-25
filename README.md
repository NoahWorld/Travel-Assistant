# 差旅报销助手

原生 macOS SwiftUI 桌面应用，用于按项目管理差旅报销。

## 已实现功能

- 录入出差开始/结束时间，自动计算出差天数。
- 录入补助标准，自动计算补助应发金额。
- 每次报销按项目管理，可录入交通费、住宿费、伙食费等费用明细。
- 可添加截图、PDF 发票等附件，附件会复制保存到本机应用数据目录。
- 支持历史项目清单、搜索、未核销总额统计。
- 支持核销/取消核销，已核销项目不计入未发总额。
- 支持导出项目汇总 PDF，方便打印。
- UI 使用系统语义颜色，跟随 macOS 深色/浅色模式。

## 运行

直接双击：

```text
dist/差旅报销助手.app
```

或者重新构建并打包：

```bash
./scripts/package_app.sh
```

## 开发

用 Xcode 打开 `Package.swift` 即可继续开发。

```bash
open Package.swift
```

也可以用命令行构建：

```bash
swift build
```

## 数据保存位置

项目历史和附件保存在当前用户的 Application Support 目录：

```text
~/Library/Application Support/TravelExpenseDesk/
```
