import AppKit
import CoreGraphics
import Foundation
import PDFKit

enum PDFExporter {
    static func export(project: ReimbursementProject, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let renderer = PDFPageRenderer(context: context, pageRect: mediaBox)
        renderer.beginPage()
        renderer.title("差旅报销项目汇总")

        renderer.section("项目信息")
        renderer.keyValueGrid([
            ("项目名称", project.name),
            ("出差人", project.traveler.isEmpty ? "-" : project.traveler),
            ("部门", project.department.isEmpty ? "-" : project.department),
            ("目的地", project.destination.isEmpty ? "-" : project.destination),
            ("事由", project.reason.isEmpty ? "-" : project.reason),
            ("城市类别", project.cityTier.rawValue),
            ("岗位类别", project.employeeLevel.rawValue),
            ("状态", project.status.rawValue)
        ])

        renderer.section("补助计算")
        renderer.keyValueGrid([
            ("开始时间", project.startDate.formatted(AppFormatters.shortDateTime)),
            ("结束时间", project.hasEndDate ? project.endDate.formatted(AppFormatters.shortDateTime) : "未结束，按导出当天计算"),
            ("出差天数", String(format: "%.1f 天", project.calculatedTravelDays)),
            ("补助标准", String(format: "%.2f 元/天", project.allowanceRate)),
            ("补助应发", money(project.allowanceAmount)),
            ("住宿标准", project.lodgingStandardText),
            ("饮食标准", project.mealStandardText),
            ("市内交通", project.localTransportStandardText),
            ("远程交通", project.longDistanceTransportStandardText),
            ("费用小计", money(project.expenseTotal))
        ])

        renderer.summary(project: project)

        renderer.section("行程与票据")
        renderer.table(
            headers: ["出发", "到达", "路线", "方式", "报销", "金额"],
            rows: project.travelSegments.map {
                [
                    $0.departAt.formatted(AppFormatters.shortDateTime),
                    $0.arriveAt.formatted(AppFormatters.shortDateTime),
                    $0.routeText,
                    $0.transportMode.rawValue,
                    $0.reimbursementDirection.rawValue,
                    money($0.amount)
                ]
            },
            widths: [92, 92, 135, 50, 78, 60]
        )

        renderer.section("费用明细")
        renderer.table(
            headers: ["日期", "类别", "说明", "金额"],
            rows: project.expenses.map {
                [
                    $0.date.formatted(AppFormatters.date),
                    $0.category.rawValue,
                    $0.note.isEmpty ? "-" : $0.note,
                    money($0.amount)
                ]
            },
            widths: [92, 80, 250, 90]
        )

        renderer.section("附件清单")
        renderer.table(
            headers: ["文件名", "类型", "添加时间"],
            rows: project.attachments.map {
                [
                    $0.fileName,
                    $0.kind.rawValue,
                    $0.addedAt.formatted(AppFormatters.shortDateTime)
                ]
            },
            widths: [300, 80, 135]
        )

        renderer.footer()
        renderer.endPage()
        appendAttachments(project.attachments, context: context, mediaBox: mediaBox)
        context.closePDF()
    }

    private static func money(_ value: Double) -> String {
        String(format: "¥%.2f", value)
    }

    private static func appendAttachments(_ attachments: [AttachmentItem], context: CGContext, mediaBox: CGRect) {
        for attachment in attachments {
            let url = URL(fileURLWithPath: attachment.storedPath)
            switch attachment.kind {
            case .image:
                guard let image = NSImage(contentsOf: url) else { continue }
                appendImagePage(image, title: attachment.fileName, context: context, mediaBox: mediaBox)
            case .pdf:
                guard let document = PDFDocument(url: url) else { continue }
                for pageIndex in 0..<document.pageCount {
                    guard let page = document.page(at: pageIndex) else { continue }
                    let thumbnail = page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
                    let title = document.pageCount > 1 ? "\(attachment.fileName) 第 \(pageIndex + 1) 页" : attachment.fileName
                    appendImagePage(thumbnail, title: title, context: context, mediaBox: mediaBox)
                }
            case .file:
                continue
            }
        }
    }

    private static func appendImagePage(_ image: NSImage, title: String, context: CGContext, mediaBox: CGRect) {
        context.beginPDFPage(nil)
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        context.translateBy(x: 0, y: mediaBox.height)
        context.scaleBy(x: 1, y: -1)

        let titleRect = CGRect(x: 42, y: 34, width: mediaBox.width - 84, height: 22)
        (title as NSString).draw(
            in: titleRect,
            withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        )

        let drawingBounds = CGRect(x: 42, y: 70, width: mediaBox.width - 84, height: mediaBox.height - 112)
        let imageRect = aspectFit(size: image.size, in: drawingBounds)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
        context.endPDFPage()
    }

    private static func aspectFit(size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }
}

private final class PDFPageRenderer {
    private let context: CGContext
    private let pageRect: CGRect
    private var y: CGFloat = 46
    private let margin: CGFloat = 42
    private var pageNumber = 0

    private var contentWidth: CGFloat {
        pageRect.width - margin * 2
    }

    init(context: CGContext, pageRect: CGRect) {
        self.context = context
        self.pageRect = pageRect
    }

    func beginPage() {
        context.beginPDFPage(nil)
        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
        y = 46
        pageNumber += 1
    }

    func endPage() {
        context.restoreGState()
        context.endPDFPage()
    }

    func title(_ text: String) {
        draw(text, rect: CGRect(x: margin, y: y, width: contentWidth, height: 30), font: .boldSystemFont(ofSize: 22))
        y += 42
    }

    func section(_ text: String) {
        ensureSpace(34)
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor)
        context.fill(CGRect(x: margin, y: y, width: contentWidth, height: 24))
        draw(text, rect: CGRect(x: margin + 8, y: y + 4, width: contentWidth - 16, height: 18), font: .boldSystemFont(ofSize: 12))
        y += 32
    }

    func keyValueGrid(_ items: [(String, String)]) {
        let rowHeight: CGFloat = 24
        let labelWidth: CGFloat = 76
        let valueWidth = (contentWidth - labelWidth * 2) / 2
        for chunkStart in stride(from: 0, to: items.count, by: 2) {
            ensureSpace(rowHeight)
            let first = items[chunkStart]
            cell(first.0, x: margin, width: labelWidth, height: rowHeight, bold: true, fill: true)
            cell(first.1, x: margin + labelWidth, width: valueWidth, height: rowHeight)
            if chunkStart + 1 < items.count {
                let second = items[chunkStart + 1]
                cell(second.0, x: margin + labelWidth + valueWidth, width: labelWidth, height: rowHeight, bold: true, fill: true)
                cell(second.1, x: margin + labelWidth * 2 + valueWidth, width: valueWidth, height: rowHeight)
            }
            y += rowHeight
        }
        y += 10
    }

    func summary(project: ReimbursementProject) {
        ensureSpace(54)
        let cardWidth = (contentWidth - 18) / 4
        let cards = [
            ("出差天数", String(format: "%.1f 天", project.calculatedTravelDays)),
            ("补助应发", String(format: "¥%.2f", project.allowanceAmount)),
            ("行程/票据费用", String(format: "¥%.2f", project.expenseTotal)),
            ("项目合计", String(format: "¥%.2f", project.totalAmount))
        ]
        for (index, card) in cards.enumerated() {
            let x = margin + CGFloat(index) * (cardWidth + 6)
            context.setStrokeColor(NSColor.separatorColor.cgColor)
            context.stroke(CGRect(x: x, y: y, width: cardWidth, height: 46))
            draw(card.0, rect: CGRect(x: x + 8, y: y + 7, width: cardWidth - 16, height: 14), font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
            draw(card.1, rect: CGRect(x: x + 8, y: y + 23, width: cardWidth - 16, height: 16), font: .boldSystemFont(ofSize: 13))
        }
        y += 58
    }

    func table(headers: [String], rows: [[String]], widths: [CGFloat]) {
        let rowHeight: CGFloat = 24
        ensureSpace(rowHeight * 2)
        var x = margin
        for (index, header) in headers.enumerated() {
            cell(header, x: x, width: widths[index], height: rowHeight, bold: true, fill: true)
            x += widths[index]
        }
        y += rowHeight

        if rows.isEmpty {
            cell("无", x: margin, width: widths.reduce(0, +), height: rowHeight)
            y += rowHeight + 10
            return
        }

        for row in rows {
            ensureSpace(rowHeight)
            x = margin
            for (index, value) in row.enumerated() {
                cell(value, x: x, width: widths[index], height: rowHeight)
                x += widths[index]
            }
            y += rowHeight
        }
        y += 10
    }

    func footer() {
        draw("打印时间：\(Date().formatted(AppFormatters.shortDateTime))    第 \(pageNumber) 页", rect: CGRect(x: margin, y: pageRect.height - 36, width: contentWidth, height: 16), font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
    }

    private func cell(_ text: String, x: CGFloat, width: CGFloat, height: CGFloat, bold: Bool = false, fill: Bool = false) {
        if fill {
            context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.72).cgColor)
            context.fill(CGRect(x: x, y: y, width: width, height: height))
        }
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.stroke(CGRect(x: x, y: y, width: width, height: height))
        draw(text, rect: CGRect(x: x + 5, y: y + 5, width: width - 10, height: height - 8), font: bold ? .boldSystemFont(ofSize: 10) : .systemFont(ofSize: 10))
    }

    private func ensureSpace(_ height: CGFloat) {
        if y + height > pageRect.height - 54 {
            footer()
            endPage()
            beginPage()
        }
    }

    private func draw(_ text: String, rect: CGRect, font: NSFont, color: NSColor = .labelColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}
