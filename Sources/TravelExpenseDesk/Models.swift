import Foundation

enum ProjectStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending = "待报销"
    case reimbursed = "已报销"
    case disbursed = "已发放"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "未核销":
            self = .pending
        case "已核销":
            self = .disbursed
        default:
            self = ProjectStatus(rawValue: rawValue) ?? .pending
        }
    }
}

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case transportation = "交通费"
    case accommodation = "住宿费"
    case meal = "伙食费"
    case materials = "材料/其他"
    case other = "其他"

    var id: String { rawValue }
}

enum AttachmentKind: String, Codable, Sendable {
    case image = "截图/图片"
    case pdf = "PDF"
    case file = "文件"
}

enum ProjectSymbol: String, Codable, CaseIterable, Identifiable, Sendable {
    case briefcase = "briefcase.fill"
    case train = "train.side.front.car"
    case airplane = "airplane"
    case car = "car.fill"
    case receipt = "receipt.fill"
    case banknote = "banknote.fill"
    case calendar = "calendar"
    case building = "building.2.fill"
    case map = "map.fill"
    case folder = "folder.fill"
    case document = "doc.text.fill"
    case checkmark = "checkmark.seal.fill"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .briefcase: "差旅"
        case .train: "高铁"
        case .airplane: "飞机"
        case .car: "打车"
        case .receipt: "票据"
        case .banknote: "补助"
        case .calendar: "周期"
        case .building: "城市"
        case .map: "路线"
        case .folder: "项目"
        case .document: "报销单"
        case .checkmark: "已发放"
        }
    }
}

enum ProjectAccent: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue
    case green
    case teal
    case orange
    case red
    case purple
    case indigo
    case gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "蓝色"
        case .green: "绿色"
        case .teal: "青色"
        case .orange: "橙色"
        case .red: "红色"
        case .purple: "紫色"
        case .indigo: "靛蓝"
        case .gray: "灰色"
        }
    }
}

enum TransportMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case highSpeedRail = "高铁"
    case flight = "飞机"
    case taxi = "打车"

    var id: String { rawValue }

    var expenseCategory: ExpenseCategory {
        switch self {
        case .highSpeedRail, .flight, .taxi:
            return .transportation
        }
    }
}

enum ReimbursementDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneWay = "单程报销"
    case roundTrip = "往返报销"

    var id: String { rawValue }
}

enum CityTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case firstTier = "北京/上海/广州/深圳/天津/重庆"
    case provincialCapital = "省会城市（含青岛、厦门、苏州）"
    case prefecture = "地级市"
    case county = "县级市"

    var id: String { rawValue }
}

enum EmployeeLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case generalManager = "一类 总经理"
    case deputyGeneralManager = "二类 副总经理"
    case departmentHead = "三类 部门负责人"
    case businessSupervisor = "四类 商务及主管"
    case technicalPresales = "五类 技术售前"
    case technicalPostsales = "六类 技术售中"

    var id: String { rawValue }
}

enum TravelStandard {
    static func lodgingLimit(for cityTier: CityTier, level: EmployeeLevel) -> Double? {
        guard level != .generalManager else { return nil }

        switch cityTier {
        case .firstTier:
            return [
                .deputyGeneralManager: 340,
                .departmentHead: 320,
                .businessSupervisor: 300,
                .technicalPresales: 280,
                .technicalPostsales: 260
            ][level]
        case .provincialCapital:
            return [
                .deputyGeneralManager: 300,
                .departmentHead: 280,
                .businessSupervisor: 260,
                .technicalPresales: 240,
                .technicalPostsales: 220
            ][level]
        case .prefecture:
            return [
                .deputyGeneralManager: 260,
                .departmentHead: 240,
                .businessSupervisor: 220,
                .technicalPresales: 200,
                .technicalPostsales: 180
            ][level]
        case .county:
            return [
                .deputyGeneralManager: 220,
                .departmentHead: 200,
                .businessSupervisor: 180,
                .technicalPresales: 160,
                .technicalPostsales: 140
            ][level]
        }
    }

    static func lodgingText(for cityTier: CityTier, level: EmployeeLevel) -> String {
        guard let limit = lodgingLimit(for: cityTier, level: level) else {
            return "取据实报"
        }
        return String(format: "%.0f 元/天", limit)
    }

    static func mealText(for level: EmployeeLevel) -> String {
        level == .generalManager ? "取据实报" : "50 元/天"
    }

    static func localTransportText(for level: EmployeeLevel) -> String {
        level == .generalManager ? "取据实报" : "50 元/天"
    }

    static func longDistanceTransportText(for level: EmployeeLevel) -> String {
        switch level {
        case .generalManager, .deputyGeneralManager, .departmentHead:
            return "飞机票经济舱 / 动车、高铁一等座"
        case .businessSupervisor, .technicalPresales, .technicalPostsales:
            return "动车、高铁等二等座"
        }
    }

    static func inferredCityTier(from text: String) -> CityTier? {
        let normalized = text.replacingOccurrences(of: "市", with: "")
        let firstTierCities = ["北京", "上海", "广州", "深圳", "天津", "重庆"]
        if firstTierCities.contains(where: { normalized.contains($0) }) {
            return .firstTier
        }

        let provincialCities = [
            "哈尔滨", "长春", "沈阳", "呼和浩特", "石家庄", "太原", "西安", "济南",
            "郑州", "南京", "合肥", "杭州", "南昌", "福州", "武汉", "长沙",
            "成都", "贵阳", "昆明", "南宁", "海口", "拉萨", "兰州", "西宁",
            "银川", "乌鲁木齐", "青岛", "厦门", "苏州"
        ]
        if provincialCities.contains(where: { normalized.contains($0) }) {
            return .provincialCapital
        }

        return nil
    }
}

struct AttachmentItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var fileName: String
    var storedPath: String
    var originalPath: String
    var kind: AttachmentKind
    var addedAt: Date = Date()
}

struct ExpenseLine: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var date: Date = Date()
    var category: ExpenseCategory = .transportation
    var note: String = ""
    var amount: Double = 0
}

struct TravelSegment: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var departAt: Date = Date()
    var arriveAt: Date = Date()
    var fromPlace: String = ""
    var toPlace: String = ""
    var transportMode: TransportMode = .highSpeedRail
    var reimbursementDirection: ReimbursementDirection = .oneWay
    var amount: Double = 0
    var sourceAttachmentID: UUID?
    var note: String = ""

    var routeText: String {
        let from = fromPlace.isEmpty ? "出发地" : fromPlace
        let to = toPlace.isEmpty ? "目的地" : toPlace
        return "\(from) → \(to)"
    }
}

struct ReimbursementProject: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var traveler: String = ""
    var department: String = ""
    var destination: String = ""
    var reason: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var hasEndDate: Bool = false
    var allowanceRate: Double = 100
    var projectSymbol: ProjectSymbol = .briefcase
    var projectAccent: ProjectAccent = .blue
    var cityTier: CityTier = .prefecture
    var employeeLevel: EmployeeLevel = .technicalPostsales
    var travelSegments: [TravelSegment] = []
    var expenses: [ExpenseLine] = []
    var attachments: [AttachmentItem] = []
    var status: ProjectStatus = .pending
    var settledAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        traveler: String = "",
        department: String = "",
        destination: String = "",
        reason: String = "",
        startDate: Date = Date(),
        endDate: Date = Date(),
        hasEndDate: Bool = false,
        allowanceRate: Double = 100,
        projectSymbol: ProjectSymbol = .briefcase,
        projectAccent: ProjectAccent = .blue,
        cityTier: CityTier = .prefecture,
        employeeLevel: EmployeeLevel = .technicalPostsales,
        travelSegments: [TravelSegment] = [],
        expenses: [ExpenseLine] = [],
        attachments: [AttachmentItem] = [],
        status: ProjectStatus = .pending,
        settledAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.traveler = traveler
        self.department = department
        self.destination = destination
        self.reason = reason
        self.startDate = startDate
        self.endDate = endDate
        self.hasEndDate = hasEndDate
        self.allowanceRate = allowanceRate
        self.projectSymbol = projectSymbol
        self.projectAccent = projectAccent
        self.cityTier = cityTier
        self.employeeLevel = employeeLevel
        self.travelSegments = travelSegments
        self.expenses = expenses
        self.attachments = attachments
        self.status = status
        self.settledAt = settledAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case traveler
        case department
        case destination
        case reason
        case startDate
        case endDate
        case hasEndDate
        case allowanceRate
        case projectSymbol
        case projectAccent
        case cityTier
        case employeeLevel
        case travelSegments
        case expenses
        case attachments
        case status
        case settledAt
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名报销项目"
        traveler = try container.decodeIfPresent(String.self, forKey: .traveler) ?? ""
        department = try container.decodeIfPresent(String.self, forKey: .department) ?? ""
        destination = try container.decodeIfPresent(String.self, forKey: .destination) ?? ""
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? Date()
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate) ?? startDate
        hasEndDate = try container.decodeIfPresent(Bool.self, forKey: .hasEndDate) ?? (endDate > startDate)
        allowanceRate = try container.decodeIfPresent(Double.self, forKey: .allowanceRate) ?? 100
        projectSymbol = try container.decodeIfPresent(ProjectSymbol.self, forKey: .projectSymbol) ?? .briefcase
        projectAccent = try container.decodeIfPresent(ProjectAccent.self, forKey: .projectAccent) ?? .blue
        cityTier = try container.decodeIfPresent(CityTier.self, forKey: .cityTier) ?? TravelStandard.inferredCityTier(from: destination) ?? .prefecture
        employeeLevel = try container.decodeIfPresent(EmployeeLevel.self, forKey: .employeeLevel) ?? .technicalPostsales
        travelSegments = try container.decodeIfPresent([TravelSegment].self, forKey: .travelSegments) ?? []
        expenses = try container.decodeIfPresent([ExpenseLine].self, forKey: .expenses) ?? []
        attachments = try container.decodeIfPresent([AttachmentItem].self, forKey: .attachments) ?? []
        status = try container.decodeIfPresent(ProjectStatus.self, forKey: .status) ?? .pending
        settledAt = try container.decodeIfPresent(Date.self, forKey: .settledAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var calculatedTravelDays: Double {
        let end = calculationEndDate
        guard end > startDate else { return 0 }
        let hours = end.timeIntervalSince(startDate) / 3600
        return ceil(hours / 12) / 2
    }

    var calculationEndDate: Date {
        hasEndDate ? endDate : Date()
    }

    var displayEndDate: Date {
        hasEndDate ? endDate : Date()
    }

    var allowanceAmount: Double {
        calculatedTravelDays * allowanceRate
    }

    var additionalExpenseTotal: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    var travelSegmentTotal: Double {
        travelSegments.reduce(0) { $0 + $1.amount }
    }

    var expenseTotal: Double {
        additionalExpenseTotal + travelSegmentTotal
    }

    var totalAmount: Double {
        allowanceAmount + expenseTotal
    }

    var isSettled: Bool {
        status == .disbursed
    }

    var lodgingStandardText: String {
        TravelStandard.lodgingText(for: cityTier, level: employeeLevel)
    }

    var mealStandardText: String {
        TravelStandard.mealText(for: employeeLevel)
    }

    var localTransportStandardText: String {
        TravelStandard.localTransportText(for: employeeLevel)
    }

    var longDistanceTransportStandardText: String {
        TravelStandard.longDistanceTransportText(for: employeeLevel)
    }
}

extension ReimbursementProject {
    static func blank(named name: String) -> ReimbursementProject {
        var project = ReimbursementProject(name: name)
        let calendar = Calendar.current
        project.startDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        project.endDate = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        project.hasEndDate = false
        project.traveler = "施碧辉"
        project.department = "研发部"
        project.reason = "售中"
        return project
    }
}
