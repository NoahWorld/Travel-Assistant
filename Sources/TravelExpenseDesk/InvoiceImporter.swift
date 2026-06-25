import AppKit
import Foundation
import PDFKit
import Vision

struct InvoiceImportResult {
    var segments: [TravelSegment] = []
    var recognizedFiles: Int = 0
    var duplicatesSkipped: Int = 0
}

enum InvoiceImporter {
    static func parse(attachments: [AttachmentItem]) -> InvoiceImportResult {
        var result = InvoiceImportResult()
        var parsedSegments: [TravelSegment] = []

        for attachment in attachments {
            let text = recognizedText(for: attachment)
            guard let segment = parseSegment(from: text, attachment: attachment) else {
                continue
            }

            result.recognizedFiles += 1
            parsedSegments.append(segment)
        }

        let attachmentsByID = Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0) })
        result.segments = TravelSegmentDeduplicator.deduplicated(parsedSegments, attachmentsByID: attachmentsByID)
        result.duplicatesSkipped = max(0, parsedSegments.count - result.segments.count)

        return result
    }

    private static func recognizedText(for attachment: AttachmentItem) -> String {
        let url = URL(fileURLWithPath: attachment.storedPath)
        let fileName = attachment.fileName.replacingOccurrences(of: "_", with: " ")

        switch attachment.kind {
        case .pdf:
            let text = PDFDocument(url: url)?.string ?? ""
            return "\(fileName)\n\(text)"
        case .image:
            return "\(fileName)\n\(recognizedImageText(from: url))"
        case .file:
            return fileName
        }
    }

    private static func recognizedImageText(from url: URL) -> String {
        guard
            let image = NSImage(contentsOf: url),
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let cgImage = bitmap.cgImage
        else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
    }

    private static func parseSegment(from text: String, attachment: AttachmentItem) -> TravelSegment? {
        let route = routePlaces(in: text)
        let amount = firstAmount(in: text) ?? 0
        let date = firstDate(in: text) ?? Date()

        guard route != nil || amount > 0 else {
            return nil
        }

        var segment = TravelSegment()
        segment.departAt = date
        segment.arriveAt = Calendar.current.date(byAdding: .hour, value: defaultTravelHours(for: transportMode(in: text)), to: date) ?? date
        segment.transportMode = transportMode(in: text)
        segment.reimbursementDirection = reimbursementDirection(in: text)
        segment.amount = amount
        segment.sourceAttachmentID = attachment.id
        segment.note = "由 \(attachment.fileName) 自动识别"

        if let route {
            segment.fromPlace = route.from
            segment.toPlace = route.to
        }

        return segment
    }

    private static func transportMode(in text: String) -> TransportMode {
        if containsAny(text, ["滴滴", "打车", "出租", "网约车", "出租车"]) {
            return .taxi
        }
        if containsAny(text, ["航班", "机票", "航空", "机场", "飞机", "登机牌"]) {
            return .flight
        }
        return .highSpeedRail
    }

    private static func reimbursementDirection(in text: String) -> ReimbursementDirection {
        containsAny(text, ["往返", "返程"]) ? .roundTrip : .oneWay
    }

    private static func defaultTravelHours(for mode: TransportMode) -> Int {
        switch mode {
        case .taxi:
            return 1
        case .highSpeedRail:
            return 3
        case .flight:
            return 2
        }
    }

    private static func routePlaces(in text: String) -> (from: String, to: String)? {
        let cities = cityMatches(in: text)
        if cities.count >= 2 {
            return (cities[0], cities[1])
        }

        let patterns = [
            #"([\p{Han}A-Za-z]{2,12})\s*(?:至|到|→|--|—|-)\s*([\p{Han}A-Za-z]{2,12})"#,
            #"出发地[:：\s]*([\p{Han}A-Za-z]{2,12}).*目的地[:：\s]*([\p{Han}A-Za-z]{2,12})"#,
            #"起点[:：\s]*([\p{Han}A-Za-z]{2,12}).*终点[:：\s]*([\p{Han}A-Za-z]{2,12})"#
        ]

        for pattern in patterns {
            guard let match = firstRegexMatch(pattern: pattern, in: text), match.count >= 3 else {
                continue
            }
            let from = cleanedPlace(match[1])
            let to = cleanedPlace(match[2])
            if !from.isEmpty, !to.isEmpty, from != to {
                return (from, to)
            }
        }

        return nil
    }

    private static func cityMatches(in text: String) -> [String] {
        let cities = [
            "北京", "上海", "广州", "深圳", "天津", "重庆", "哈尔滨", "大庆", "齐齐哈尔", "牡丹江",
            "长春", "沈阳", "大连", "呼和浩特", "石家庄", "太原", "西安", "济南", "青岛", "郑州",
            "南京", "苏州", "合肥", "杭州", "宁波", "南昌", "福州", "厦门", "武汉", "长沙",
            "成都", "贵阳", "昆明", "南宁", "海口", "拉萨", "兰州", "西宁", "银川", "乌鲁木齐"
        ]

        let matches = cities.compactMap { city -> (city: String, lowerBound: String.Index)? in
            guard let range = text.range(of: city) else { return nil }
            return (city, range.lowerBound)
        }
        .sorted { $0.lowerBound < $1.lowerBound }
        .map(\.city)

        var unique: [String] = []
        for city in matches where unique.last != city {
            unique.append(city)
        }
        return unique
    }

    private static func firstDate(in text: String) -> Date? {
        let currentYear = Calendar.current.component(.year, from: Date())
        let patterns = [
            #"(20\d{2})[年/\-.](\d{1,2})[月/\-.](\d{1,2})日?\s*(\d{1,2})?[:：时]?(\d{1,2})?"#,
            #"(\d{1,2})[月/\-.](\d{1,2})日?\s*(\d{1,2})?[:：时]?(\d{1,2})?"#
        ]

        for (index, pattern) in patterns.enumerated() {
            guard let match = firstRegexMatch(pattern: pattern, in: text) else { continue }
            var components = DateComponents()
            if index == 0 {
                components.year = Int(match[safe: 1] ?? "")
                components.month = Int(match[safe: 2] ?? "")
                components.day = Int(match[safe: 3] ?? "")
                components.hour = Int(match[safe: 4] ?? "") ?? 9
                components.minute = Int(match[safe: 5] ?? "") ?? 0
            } else {
                components.year = currentYear
                components.month = Int(match[safe: 1] ?? "")
                components.day = Int(match[safe: 2] ?? "")
                components.hour = Int(match[safe: 3] ?? "") ?? 9
                components.minute = Int(match[safe: 4] ?? "") ?? 0
            }
            if let date = Calendar.current.date(from: components) {
                return date
            }
        }

        return nil
    }

    private static func firstAmount(in text: String) -> Double? {
        let amountPatterns = [
            #"(?:金额|合计|票价|费用|实付|总价|￥|¥)\s*[:：]?\s*(\d{1,5}(?:\.\d{1,2})?)"#,
            #"(\d{1,5}\.\d{1,2})"#
        ]

        for pattern in amountPatterns {
            let matches = regexMatches(pattern: pattern, in: text)
            let amounts = matches.compactMap { groups -> Double? in
                guard groups.count > 1 else { return nil }
                return Double(groups[1])
            }
            let plausible = amounts.filter { $0 > 0 && $0 < 100_000 }
            if let amount = plausible.max() {
                return amount
            }
        }

        return nil
    }

    private static func cleanedPlace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "站", with: "")
            .replacingOccurrences(of: "机场", with: "")
            .replacingOccurrences(of: "出发", with: "")
            .replacingOccurrences(of: "到达", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func firstRegexMatch(pattern: String, in text: String) -> [String]? {
        regexMatches(pattern: pattern, in: text).first
    }

    private static func regexMatches(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                guard let swiftRange = Range(range, in: text) else { return "" }
                return String(text[swiftRange])
            }
        }
    }
}

enum TravelSegmentDeduplicator {
    static func deduplicated(_ segments: [TravelSegment], attachmentsByID: [UUID: AttachmentItem]) -> [TravelSegment] {
        var kept: [TravelSegment] = []

        for segment in segments {
            guard let duplicateIndex = kept.firstIndex(where: {
                isDuplicateDidiPair($0, segment, attachmentsByID: attachmentsByID)
            }) else {
                kept.append(segment)
                continue
            }

            if score(segment, attachmentsByID: attachmentsByID) > score(kept[duplicateIndex], attachmentsByID: attachmentsByID) {
                kept[duplicateIndex] = segment
            }
        }

        return kept
    }

    private static func isDuplicateDidiPair(
        _ lhs: TravelSegment,
        _ rhs: TravelSegment,
        attachmentsByID: [UUID: AttachmentItem]
    ) -> Bool {
        guard lhs.transportMode == .taxi, rhs.transportMode == .taxi else { return false }

        let lhsKind = sourceKind(for: lhs, attachmentsByID: attachmentsByID)
        let rhsKind = sourceKind(for: rhs, attachmentsByID: attachmentsByID)
        let isTripAndInvoicePair = (lhsKind == .didiTrip && rhsKind == .didiInvoice)
            || (lhsKind == .didiInvoice && rhsKind == .didiTrip)

        guard isTripAndInvoicePair else { return false }
        guard amountCents(lhs.amount) == amountCents(rhs.amount) else { return false }

        return datesAreClose(lhs.departAt, rhs.departAt)
    }

    private static func score(_ segment: TravelSegment, attachmentsByID: [UUID: AttachmentItem]) -> Int {
        let kind = sourceKind(for: segment, attachmentsByID: attachmentsByID)
        var score = kind.priority

        if !segment.fromPlace.isEmpty {
            score += 1
        }
        if !segment.toPlace.isEmpty {
            score += 1
        }

        return score
    }

    private static func sourceKind(for segment: TravelSegment, attachmentsByID: [UUID: AttachmentItem]) -> SegmentSourceKind {
        let text = sourceText(for: segment, attachmentsByID: attachmentsByID)
        guard text.localizedCaseInsensitiveContains("滴滴") else {
            return .other
        }

        if text.localizedCaseInsensitiveContains("行程") {
            return .didiTrip
        }
        if text.localizedCaseInsensitiveContains("发票") {
            return .didiInvoice
        }

        return .other
    }

    private static func sourceText(for segment: TravelSegment, attachmentsByID: [UUID: AttachmentItem]) -> String {
        var parts = [segment.note]
        if let sourceAttachmentID = segment.sourceAttachmentID,
           let attachment = attachmentsByID[sourceAttachmentID] {
            parts.append(attachment.fileName)
            parts.append(attachment.originalPath)
            parts.append(attachment.storedPath)
        }

        return parts.joined(separator: " ")
    }

    private static func amountCents(_ amount: Double) -> Int {
        Int((amount * 100).rounded())
    }

    private static func datesAreClose(_ lhs: Date, _ rhs: Date) -> Bool {
        let calendar = Calendar.current
        let lhsDay = calendar.startOfDay(for: lhs)
        let rhsDay = calendar.startOfDay(for: rhs)
        let distance = abs(calendar.dateComponents([.day], from: lhsDay, to: rhsDay).day ?? 0)
        return distance <= 31
    }

    private enum SegmentSourceKind {
        case didiTrip
        case didiInvoice
        case other

        var priority: Int {
            switch self {
            case .didiTrip:
                return 20
            case .didiInvoice:
                return 10
            case .other:
                return 0
            }
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
