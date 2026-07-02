import AppKit
import Foundation
import PDFKit
import Vision

struct InvoiceImportResult: Sendable {
    var segments: [TravelSegment] = []
    var recognizedFiles: Int = 0
    var duplicatesSkipped: Int = 0
}

private struct RecognizedInvoiceDocument {
    var text: String
    var sourceKind: SegmentSourceKind
}

private struct ParsedTravelSegment {
    var segment: TravelSegment
    var sourceKind: SegmentSourceKind
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

enum InvoiceImporter {
    static func parse(attachments: [AttachmentItem]) -> InvoiceImportResult {
        var result = InvoiceImportResult()
        var parsedSegments: [ParsedTravelSegment] = []

        for attachment in attachments {
            let document = recognizedDocument(for: attachment)
            guard let segment = parseSegment(from: document, attachment: attachment) else {
                continue
            }

            result.recognizedFiles += 1
            parsedSegments.append(segment)
        }

        let deduplicatedSegments = TravelSegmentDeduplicator.deduplicated(parsedSegments)
        result.segments = deduplicatedSegments.map(\.segment)
        result.duplicatesSkipped = max(0, parsedSegments.count - result.segments.count)

        return result
    }

    private static func recognizedDocument(for attachment: AttachmentItem) -> RecognizedInvoiceDocument {
        let url = URL(fileURLWithPath: attachment.storedPath)
        let text: String

        switch attachment.kind {
        case .pdf:
            let document = PDFDocument(url: url)
            let embeddedText = document?.string ?? ""
            if let document, shouldRunOCRFallback(for: embeddedText) {
                text = [embeddedText, recognizedPDFImageText(from: document)]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
            } else {
                text = embeddedText
            }
        case .image:
            text = recognizedImageText(from: url)
        case .file:
            text = ""
        }

        return RecognizedInvoiceDocument(text: text, sourceKind: sourceKind(in: text))
    }

    private static func shouldRunOCRFallback(for text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.count < 40 || bestAmount(in: trimmedText) == nil
    }

    private static func recognizedPDFImageText(from document: PDFDocument) -> String {
        let pageCount = min(document.pageCount, 3)
        guard pageCount > 0 else { return "" }

        return (0..<pageCount).compactMap { pageIndex -> String? in
            guard let page = document.page(at: pageIndex) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { return nil }

            let width: CGFloat = 1800
            let height = width * bounds.height / bounds.width
            let image = page.thumbnail(of: NSSize(width: width, height: height), for: .mediaBox)
            let text = recognizedText(from: image)
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
        .joined(separator: "\n")
    }

    private static func recognizedImageText(from url: URL) -> String {
        guard let image = NSImage(contentsOf: url) else { return "" }
        return recognizedText(from: image)
    }

    private static func recognizedText(from image: NSImage) -> String {
        guard let cgImage = cgImage(from: image) else { return "" }

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

    private static func cgImage(from image: NSImage) -> CGImage? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage
        }

        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.cgImage
    }

    private static func parseSegment(
        from document: RecognizedInvoiceDocument,
        attachment: AttachmentItem
    ) -> ParsedTravelSegment? {
        let text = document.text
        let route = routePlaces(in: text)
        let amount = bestAmount(in: text) ?? 0
        let date = travelDate(in: text) ?? invoiceDate(in: text) ?? Date()

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

        return ParsedTravelSegment(segment: segment, sourceKind: document.sourceKind)
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
        let patterns = [
            #"行\s*程\s*信\s*息[:：\s]*(?:20\d{2}[-年/\.]\d{1,2}[-月/\.]\d{1,2}日?\s*)?([\p{Han}A-Za-z]{2,12})\s*(?:至|到|→|--|—|-|_)\s*([\p{Han}A-Za-z]{2,12})"#,
            #"([\p{Han}A-Za-z]{2,12})站\s+([\p{Han}A-Za-z]{2,12})站"#,
            #"出\s*发\s*地[:：\s]*([\p{Han}A-Za-z]{2,12}).{0,80}?到\s*达\s*地[:：\s]*([\p{Han}A-Za-z]{2,12})"#,
            #"出\s*发\s*地[:：\s]*([\p{Han}A-Za-z]{2,12}).{0,80}?目\s*的\s*地[:：\s]*([\p{Han}A-Za-z]{2,12})"#,
            #"起\s*点[:：\s]*([\p{Han}A-Za-z]{2,20}).{0,80}?终\s*点[:：\s]*([\p{Han}A-Za-z]{2,20})"#
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

        return didiAirportRoute(in: text)
    }

    private static func didiAirportRoute(in text: String) -> (from: String, to: String)? {
        guard text.localizedCaseInsensitiveContains("滴滴") else { return nil }
        guard let city = cityMatches(in: text).first else { return nil }

        let rowText: String
        if let headerRange = text.range(of: "备注") {
            rowText = String(text[headerRange.upperBound...])
        } else {
            rowText = text
        }

        guard let airportRange = airportTokenRange(in: rowText) else { return nil }
        let airportName = airportName(in: text, fallbackCity: city)
        let cityName = city.replacingOccurrences(of: "市", with: "")
        let beforeAirport = String(rowText[..<airportRange.lowerBound])
        let afterAirport = String(rowText[airportRange.upperBound...])
        let localDestinationTerms = ["怡景江南", "阳光大道", "庙山", "小区", "酒店", "公司", "家"]

        if containsAny(afterAirport, localDestinationTerms) {
            return (airportName, cityName)
        }
        if containsAny(beforeAirport, localDestinationTerms) {
            return (cityName, airportName)
        }

        return nil
    }

    private static func airportTokenRange(in text: String) -> Range<String.Index>? {
        ["机场", "航站楼", "天河-T", "天河T", "天河国际"].compactMap { token in
            text.range(of: token)
        }
        .sorted { $0.lowerBound < $1.lowerBound }
        .first
    }

    private static func airportName(in text: String, fallbackCity: String) -> String {
        if text.contains("天河") {
            return "武汉天河机场"
        }
        if text.contains("首都") {
            return "北京首都机场"
        }
        if text.contains("大兴") {
            return "北京大兴机场"
        }
        return "\(fallbackCity.replacingOccurrences(of: "市", with: ""))机场"
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

    private static func travelDate(in text: String) -> Date? {
        if let date = didiBoardingDate(in: text) {
            return date
        }

        let patterns = [
            #"行\s*程\s*信\s*息[:：\s]*(20\d{2})[-年/\.](\d{1,2})[-月/\.](\d{1,2})日?\s*(\d{1,2})?[:：时]?(\d{1,2})?"#,
            #"(20\d{2})年(\d{1,2})月(\d{1,2})日\s*(\d{1,2})[:：](\d{1,2})\s*开"#,
            #"出\s*行\s*日\s*期[:：\s]*(20\d{2})[-年/\.](\d{1,2})[-月/\.](\d{1,2})日?\s*(\d{1,2})?[:：时]?(\d{1,2})?"#,
            #"行\s*程\s*起\s*止\s*日\s*期[:：\s]*(20\d{2})[-年/\.](\d{1,2})[-月/\.](\d{1,2})日?"#
        ]

        for pattern in patterns {
            guard let match = firstRegexMatch(pattern: pattern, in: text) else { continue }
            if let date = date(
                year: match[safe: 1],
                month: match[safe: 2],
                day: match[safe: 3],
                hour: match[safe: 4],
                minute: match[safe: 5]
            ) {
                return date
            }
        }

        return nil
    }

    private static func didiBoardingDate(in text: String) -> Date? {
        guard text.localizedCaseInsensitiveContains("滴滴") else { return nil }
        guard let period = firstRegexMatch(
            pattern: #"行\s*程\s*起\s*止\s*日\s*期[:：\s]*(20\d{2})[-年/\.](\d{1,2})[-月/\.](\d{1,2})日?"#,
            in: text
        ) else {
            return nil
        }

        guard let year = period[safe: 1] else { return nil }
        let boardingPattern = #"(\d{1,2})-(\d{1,2})\s+(\d{1,2})\s*[:：]\s*(\d{1,2})"#
        if let boarding = firstRegexMatch(pattern: boardingPattern, in: text),
           let month = boarding[safe: 1],
           let day = boarding[safe: 2] {
            return date(
                year: year,
                month: month,
                day: day,
                hour: boarding[safe: 3],
                minute: boarding[safe: 4]
            )
        }

        return date(year: year, month: period[safe: 2], day: period[safe: 3], hour: nil, minute: nil)
    }

    private static func invoiceDate(in text: String) -> Date? {
        if let match = firstRegexMatch(
            pattern: #"开\s*票\s*日\s*期[:：\s]*(20\d{2})[年/\-.](\d{1,2})[月/\-.](\d{1,2})日?\s*(\d{1,2})?[:：时]?(\d{1,2})?"#,
            in: text
        ) {
            return date(
                year: match[safe: 1],
                month: match[safe: 2],
                day: match[safe: 3],
                hour: match[safe: 4],
                minute: match[safe: 5]
            )
        }

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

    private static func date(
        year: String?,
        month: String?,
        day: String?,
        hour: String?,
        minute: String?
    ) -> Date? {
        var components = DateComponents()
        components.year = Int(year ?? "")
        components.month = Int(month ?? "")
        components.day = Int(day ?? "")
        components.hour = Int(hour ?? "") ?? 9
        components.minute = Int(minute ?? "") ?? 0
        return Calendar.current.date(from: components)
    }

    private static func bestAmount(in text: String) -> Double? {
        let normalizedText = text.replacingOccurrences(of: ",", with: "")
        var candidates: [(amount: Double, priority: Int)] = []

        let amountPatterns: [(pattern: String, priority: Int)] = [
            (#"价\s*税\s*合\s*计[\s\S]{0,120}?小\s*写[\s\S]{0,30}?[¥￥]?\s*(\d{1,6}(?:\.\d{1,2})?)"#, 100),
            (#"小\s*写[\s\S]{0,20}?[¥￥]\s*(\d{1,6}(?:\.\d{1,2})?)"#, 95),
            (#"小\s*写[\s\S]{0,10}?(\d{1,6}(?:\.\d{1,2})?)"#, 90),
            (#"合\s*计\s*(\d{1,6}(?:\.\d{1,2})?)\s*元"#, 85),
            (#"票\s*价\s*[:：]?\s*[¥￥]?\s*(\d{1,6}(?:\.\d{1,2})?)"#, 80),
            (#"实\s*付(?:\s*金\s*额)?\s*[:：]?\s*[¥￥]?\s*(\d{1,6}(?:\.\d{1,2})?)"#, 80),
            (#"总\s*价\s*[:：]?\s*[¥￥]?\s*(\d{1,6}(?:\.\d{1,2})?)"#, 75),
            (#"[¥￥]\s*(\d{1,6}(?:\.\d{1,2})?)"#, 60)
        ]

        for amountPattern in amountPatterns {
            for match in regexMatches(pattern: amountPattern.pattern, in: normalizedText) {
                guard let amount = parseAmount(match[safe: 1]) else { continue }
                guard amount > 0, amount < 100_000 else { continue }
                candidates.append((amount, amountPattern.priority))
            }
        }

        return candidates.sorted {
            if $0.priority == $1.priority {
                return $0.amount > $1.amount
            }
            return $0.priority > $1.priority
        }
        .first?.amount
    }

    private static func parseAmount(_ value: String?) -> Double? {
        guard let value else { return nil }
        return Double(value.replacingOccurrences(of: ",", with: ""))
    }

    private static func sourceKind(in text: String) -> SegmentSourceKind {
        if containsAny(text, ["滴滴出行-行程单", "DIDI TRAVEL", "共1笔行程", "笔行程"]) {
            return .didiTrip
        }

        if containsAny(text, ["滴滴出行科技有限公司", "旅客运输服务"]) {
            return .didiInvoice
        }

        return .other
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
    fileprivate static func deduplicated(_ candidates: [ParsedTravelSegment]) -> [ParsedTravelSegment] {
        var kept: [ParsedTravelSegment] = []

        for candidate in candidates {
            guard let duplicateIndex = kept.firstIndex(where: {
                isDuplicateDidiPair($0, candidate)
            }) else {
                kept.append(candidate)
                continue
            }

            if score(candidate) > score(kept[duplicateIndex]) {
                kept[duplicateIndex] = candidate
            }
        }

        return kept
    }

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
        _ lhs: ParsedTravelSegment,
        _ rhs: ParsedTravelSegment
    ) -> Bool {
        guard lhs.segment.transportMode == .taxi, rhs.segment.transportMode == .taxi else { return false }

        let isTripAndInvoicePair = (lhs.sourceKind == .didiTrip && rhs.sourceKind == .didiInvoice)
            || (lhs.sourceKind == .didiInvoice && rhs.sourceKind == .didiTrip)

        guard isTripAndInvoicePair else { return false }
        guard amountCents(lhs.segment.amount) == amountCents(rhs.segment.amount) else { return false }

        return datesAreClose(lhs.segment.departAt, rhs.segment.departAt)
    }

    private static func score(_ candidate: ParsedTravelSegment) -> Int {
        var score = candidate.sourceKind.priority

        if !candidate.segment.fromPlace.isEmpty {
            score += 1
        }
        if !candidate.segment.toPlace.isEmpty {
            score += 1
        }

        return score
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

}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
