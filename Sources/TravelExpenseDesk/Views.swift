import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

private enum ProjectListFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case pending = "待报销"
    case reimbursed = "已报销"
    case disbursed = "已发放"

    var id: String { rawValue }
}

private enum WorkbenchSection {
    case overview
    case projects
    case standards
    case settings
}

private enum AppSurface {
    static let pageBackground = Color(nsColor: dynamicColor(
        light: NSColor(calibratedRed: 0.955, green: 0.965, blue: 0.975, alpha: 1),
        dark: NSColor(calibratedRed: 0.075, green: 0.080, blue: 0.090, alpha: 1)
    ))
    static let sidebar = Color(nsColor: dynamicColor(
        light: NSColor(calibratedRed: 0.975, green: 0.980, blue: 0.986, alpha: 1),
        dark: NSColor(calibratedRed: 0.095, green: 0.100, blue: 0.112, alpha: 1)
    ))
    static let card = Color(nsColor: dynamicColor(
        light: NSColor(calibratedWhite: 1, alpha: 1),
        dark: NSColor(calibratedRed: 0.125, green: 0.132, blue: 0.146, alpha: 1)
    ))
    static let cardSubtle = Color(nsColor: dynamicColor(
        light: NSColor(calibratedRed: 0.982, green: 0.986, blue: 0.992, alpha: 1),
        dark: NSColor(calibratedRed: 0.155, green: 0.162, blue: 0.178, alpha: 1)
    ))
    static let mutedFill = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.075)

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDarkMode ? dark : light
        }
    }
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var searchText = ""
    @State private var listFilter: ProjectListFilter = .all
    @AppStorage("travelExpenseDesk.sidebarCollapsed") private var isSidebarCollapsed = false
    @State private var selectedSection: WorkbenchSection = .overview

    private var filteredProjects: [ReimbursementProject] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [ReimbursementProject]
        if trimmedSearch.isEmpty {
            candidates = store.projects
        } else {
            candidates = store.projects.filter {
                $0.name.localizedCaseInsensitiveContains(trimmedSearch)
                    || $0.destination.localizedCaseInsensitiveContains(trimmedSearch)
                    || $0.traveler.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }

        let statusFiltered = candidates.filter { project in
            switch listFilter {
            case .all:
                return true
            case .pending:
                return project.status == .pending
            case .reimbursed:
                return project.status == .reimbursed
            case .disbursed:
                return project.status == .disbursed
            }
        }

        return statusFiltered.sorted {
            if $0.startDate == $1.startDate {
                return $0.createdAt > $1.createdAt
            }
            return $0.startDate > $1.startDate
        }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if isSidebarCollapsed {
                    collapsedNavigationRail
                } else {
                    navigationSidebar
                }

                Divider()

                if selectedSection == .projects {
                    projectListColumn
                        .frame(width: projectListWidth(for: proxy.size.width))

                    Divider()
                }

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppSurface.pageBackground)
        }
        .background(AppSurface.pageBackground)
        .alert("确认删除项目？", isPresented: Binding(
            get: { store.projectPendingDeletionID != nil },
            set: { if !$0 { store.projectPendingDeletionID = nil } }
        )) {
            Button("删除", role: .destructive) {
                store.confirmPendingProjectDeletion()
            }
            Button("取消", role: .cancel) {
                store.projectPendingDeletionID = nil
            }
        } message: {
            Text("删除后会移除该项目记录和已导入的附件文件。")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .overview:
            OverviewDashboardPage(
                projects: store.projects,
                accent: store.appThemeAccent.color,
                onNewProject: {
                    store.createProject()
                    selectedSection = .projects
                },
                onSelectProject: { projectID in
                    store.selectedProjectID = projectID
                    selectedSection = .projects
                }
            )
        case .projects:
            if let selectedID = store.selectedProjectID,
               let index = store.projects.firstIndex(where: { $0.id == selectedID }) {
                ProjectDetailView(project: $store.projects[index])
                    .id(selectedID)
            } else {
                EmptyStateView()
            }
        case .standards:
            ReimbursementStandardsPage()
        case .settings:
            AppSettingsView(
                appearanceMode: $store.appAppearanceMode,
                themeAccent: $store.appThemeAccent,
                showsStageDayInMenuBar: $store.showsStageDayInMenuBar
            )
        }
    }

    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Spacer()

                Button {
                    setSidebarCollapsed(true)
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.callout.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
                .help("收起侧栏")
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                SidebarNavButton(title: "概览", icon: "chart.bar.xaxis", isSelected: selectedSection == .overview) {
                    selectedSection = .overview
                }

                SidebarNavSection(title: "管理") {
                    SidebarNavButton(title: "项目报销", icon: "briefcase.fill", isSelected: selectedSection == .projects) {
                        selectedSection = .projects
                    }
                }

                SidebarNavSection(title: "数据") {
                    SidebarNavButton(title: "报销标准", icon: "list.clipboard", isSelected: selectedSection == .standards) {
                        selectedSection = .standards
                    }
                }

                SidebarNavSection(title: "设置") {
                    SidebarNavButton(title: "系统设置", icon: "gearshape", isSelected: selectedSection == .settings) {
                        selectedSection = .settings
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Label(store.appAppearanceMode.title, systemImage: store.appAppearanceMode.icon)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 128, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(width: 152, alignment: .leading)
        .background(AppSurface.sidebar)
    }

    private var collapsedNavigationRail: some View {
        VStack(spacing: 12) {
            Button {
                setSidebarCollapsed(false)
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 38)
            }
            .buttonStyle(.plain)
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppSurface.hairline)
            )
            .help("展开侧栏")

            Image(systemName: "creditcard.viewfinder")
                .font(.headline.weight(.semibold))
                .foregroundStyle(store.appThemeAccent.color)
                .frame(width: 40, height: 40)
                .background(store.appThemeAccent.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .help("差旅报销助手")

            Divider()

            VStack(spacing: 8) {
                SidebarRailButton(icon: "chart.bar.xaxis", isSelected: selectedSection == .overview, help: "概览") {
                    selectedSection = .overview
                }

                SidebarRailButton(icon: "folder.fill", isSelected: selectedSection == .projects, help: "项目报销") {
                    selectedSection = .projects
                }

                SidebarRailButton(icon: "list.clipboard", isSelected: selectedSection == .standards, help: "报销标准") {
                    selectedSection = .standards
                }
            }

            Spacer()

            VStack(spacing: 8) {
                SidebarRailButton(icon: "plus", isSelected: false, help: "新建报销单") {
                    store.createProject()
                    selectedSection = .projects
                }

                SidebarRailButton(icon: "gearshape", isSelected: selectedSection == .settings, help: "系统设置") {
                    selectedSection = .settings
                }
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 14)
        .frame(width: 64)
        .background(AppSurface.sidebar)
    }

    private func setSidebarCollapsed(_ collapsed: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isSidebarCollapsed = collapsed
        }
    }

    private func projectListWidth(for totalWidth: CGFloat) -> CGFloat {
        guard selectedSection == .projects else { return 0 }
        let sidebarWidth: CGFloat = isSidebarCollapsed ? 64 : 152
        let availableWidth = max(totalWidth - sidebarWidth, 0)
        return min(340, max(292, availableWidth * 0.28))
    }

    private var projectListColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("报销单")
                        .font(.title2.bold())
                    Text("共 \(filteredProjects.count) 条")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.createProject()
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(store.appThemeAccent.color)
                .help("新建报销单")
            }

            searchField

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ProjectListFilter.allCases) { filter in
                        FilterChip(title: filter.rawValue, isSelected: listFilter == filter, accent: store.appThemeAccent.color) {
                            listFilter = filter
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            ProjectListSummaryBar(
                count: store.unpaidCount,
                total: store.unpaidTotal.formatted(AppFormatters.currency),
                accent: store.appThemeAccent.color
            )

            HStack {
                Text("报销列表")
                    .font(.headline)
                Spacer()
                Button {
                    store.requestDeleteSelectedProject()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedProjectID == nil)
                .help("删除选中的项目")
            }

            if filteredProjects.isEmpty {
                ContentUnavailableView(
                    "没有匹配项目",
                    systemImage: "tray",
                    description: Text("调整搜索或筛选条件。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProjects) { project in
                            Button {
                                store.selectedProjectID = project.id
                            } label: {
                                ProjectListCard(
                                    project: project,
                                    isSelected: store.selectedProjectID == project.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Text(selectedProjectFooterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .background(AppSurface.card)
    }

    private var selectedProjectFooterText: String {
        guard let selectedID = store.selectedProjectID,
              let selected = store.projects.first(where: { $0.id == selectedID }) else {
            return "未选择报销单"
        }
        return "当前：\(selected.name)"
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("搜索项目、地点、出差人", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppSurface.hairline)
        )
    }
}

private struct SidebarNavSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            content
        }
    }
}

private struct SidebarNavButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarRailButton: View {
    let icon: String
    let isSelected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .frame(width: 40, height: 36)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct QuickCreatePanel: View {
    let accent: Color
    let onNewProject: () -> Void
    let onStandards: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("快速创建")
                    .font(.callout.bold())
                Spacer()
                Button(action: onNewProject) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }

            QuickCreateButton(title: "新建报销单", icon: "doc.badge.plus", action: onNewProject)
            QuickCreateButton(title: "创建项目", icon: "folder.badge.plus", action: onNewProject)
            QuickCreateButton(title: "导入发票", icon: "doc.text.viewfinder") {}
            QuickCreateButton(title: "报销标准", icon: "list.clipboard", action: onStandards)
        }
        .padding(12)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
    }
}

private struct QuickCreateButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? accent : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isSelected ? accent.opacity(0.10) : AppSurface.cardSubtle, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? accent.opacity(0.35) : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectListSummaryBar: View {
    let count: Int
    let total: String
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.callout.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text("未发放")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(count) 单")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            }

            Divider()
                .frame(height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("未发放总额")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(total)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
    }
}

private struct ProjectListMetricCard: View {
    let title: String
    let value: String
    let footnote: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
    }
}

private struct ProjectListCard: View {
    let project: ReimbursementProject
    let isSelected: Bool

    private var accent: Color { project.projectAccent.color }

    var body: some View {
        HStack(spacing: 11) {
            ProjectIconBadge(symbol: project.projectSymbol, accent: project.projectAccent, size: 38)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(project.name)
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(project.totalAmount.formatted(AppFormatters.currency))
                        .font(.callout.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                HStack(spacing: 12) {
                    Text("出差人：\(project.traveler.isEmpty ? "未填" : project.traveler)")
                    Text("目的地：\(project.destination.isEmpty ? "未填" : project.destination)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack {
                    Text(projectDateRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    StatusBadge(status: project.status)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? accent.opacity(0.07) : AppSurface.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? accent.opacity(0.72) : AppSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var projectDateRangeText: String {
        if project.hasEndDate {
            return "\(project.startDate.formatted(AppFormatters.date)) - \(project.endDate.formatted(AppFormatters.date))"
        }
        return "\(project.startDate.formatted(AppFormatters.date)) - 至今"
    }
}

private struct OverviewDashboardPage: View {
    let projects: [ReimbursementProject]
    let accent: Color
    let onNewProject: () -> Void
    let onSelectProject: (ReimbursementProject.ID) -> Void

    private var sortedProjects: [ReimbursementProject] {
        projects.sorted {
            if $0.startDate == $1.startDate {
                return $0.createdAt > $1.createdAt
            }
            return $0.startDate > $1.startDate
        }
    }

    private var totalAmount: Double {
        projects.reduce(0) { $0 + $1.totalAmount }
    }

    private var openProjects: [ReimbursementProject] {
        projects.filter { $0.status != .disbursed }
    }

    private var openAmount: Double {
        openProjects.reduce(0) { $0 + $1.totalAmount }
    }

    private var disbursedAmount: Double {
        projects.filter { $0.status == .disbursed }.reduce(0) { $0 + $1.totalAmount }
    }

    private var reimbursedAmount: Double {
        projects.filter { $0.status == .reimbursed }.reduce(0) { $0 + $1.totalAmount }
    }

    private var monthlySummaries: [MonthlyReimbursementSummary] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: projects) { project in
            let components = calendar.dateComponents([.year, .month], from: project.startDate)
            return calendar.date(from: components) ?? calendar.startOfDay(for: project.startDate)
        }
        return grouped
            .map { MonthlyReimbursementSummary(month: $0.key, projects: $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = proxy.size.width < 760 ? 14 : 24

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summaryGrid
                    statusBreakdown
                    historySection
                    recentProjectsSection
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 22)
                .frame(maxWidth: 1180, alignment: .leading)
            }
            .background(AppSurface.pageBackground)
        }
        .background(AppSurface.pageBackground)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                overviewTitle
                Spacer()
                Button(action: onNewProject) {
                    Label("新建报销单", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }

            VStack(alignment: .leading, spacing: 12) {
                overviewTitle
                Button(action: onNewProject) {
                    Label("新建报销单", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
    }

    private var overviewTitle: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("概览")
                    .font(.title2.bold())
                Text("按状态、月份和最近项目汇总历史报销情况。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            OverviewMetricCard(
                title: "历史合计",
                value: totalAmount.formatted(AppFormatters.currency),
                footnote: "\(projects.count) 单全部报销记录",
                icon: "sum",
                tint: accent
            )
            OverviewMetricCard(
                title: "待处理金额",
                value: openAmount.formatted(AppFormatters.currency),
                footnote: "\(openProjects.count) 单待报销/已报销未发放",
                icon: "clock.badge.exclamationmark",
                tint: .orange
            )
            OverviewMetricCard(
                title: "已报销金额",
                value: reimbursedAmount.formatted(AppFormatters.currency),
                footnote: "\(projects.filter { $0.status == .reimbursed }.count) 单已报销",
                icon: "doc.text.fill",
                tint: .blue
            )
            OverviewMetricCard(
                title: "已发放金额",
                value: disbursedAmount.formatted(AppFormatters.currency),
                footnote: "\(projects.filter { $0.status == .disbursed }.count) 单已闭环",
                icon: "checkmark.seal.fill",
                tint: .green
            )
        }
    }

    private var statusBreakdown: some View {
        Panel(title: "状态分布", systemImage: "chart.pie.fill", accent: accent) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(ProjectStatus.allCases) { status in
                    let statusProjects = projects.filter { $0.status == status }
                    let statusAmount = statusProjects.reduce(0) { $0 + $1.totalAmount }
                    OverviewStatusCard(
                        status: status,
                        count: statusProjects.count,
                        amount: statusAmount
                    )
                }
            }
        }
    }

    private var historySection: some View {
        Panel(title: "月份历史", systemImage: "clock.arrow.circlepath", accent: accent) {
            if monthlySummaries.isEmpty {
                ContentUnavailableView(
                    "暂无历史报销",
                    systemImage: "tray",
                    description: Text("新建报销单后，这里会按月份自动汇总。")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                let maxAmount = max(monthlySummaries.map(\.totalAmount).max() ?? 1, 1)
                VStack(spacing: 10) {
                    ForEach(monthlySummaries) { summary in
                        OverviewMonthRow(summary: summary, maxAmount: maxAmount)
                    }
                }
            }
        }
    }

    private var recentProjectsSection: some View {
        Panel(title: "最近报销单", systemImage: "list.bullet.rectangle", accent: accent) {
            if sortedProjects.isEmpty {
                ContentUnavailableView(
                    "暂无报销单",
                    systemImage: "doc.badge.plus",
                    description: Text("点击右上角新建第一张报销单。")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedProjects.prefix(6)) { project in
                        OverviewProjectRow(project: project) {
                            onSelectProject(project.id)
                        }
                    }
                }
            }
        }
    }
}

private struct OverviewMetricCard: View {
    let title: String
    let value: String
    let footnote: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
                Spacer()
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
    }
}

private struct OverviewStatusCard: View {
    let status: ProjectStatus
    let count: Int
    let amount: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(status: status)
                Spacer()
                Text("\(count) 单")
                    .font(.callout.bold())
                    .foregroundStyle(status.overviewTint)
            }

            Text(amount.formatted(AppFormatters.currency))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.overviewTint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(status.overviewTint.opacity(0.18)))
    }
}

private struct MonthlyReimbursementSummary: Identifiable {
    let month: Date
    let projects: [ReimbursementProject]

    var id: Date { month }
    var totalAmount: Double { projects.reduce(0) { $0 + $1.totalAmount } }
    var pendingCount: Int { projects.filter { $0.status == .pending }.count }
    var reimbursedCount: Int { projects.filter { $0.status == .reimbursed }.count }
    var disbursedCount: Int { projects.filter { $0.status == .disbursed }.count }

    var monthTitle: String {
        month.formatted(.dateTime.year().month())
    }
}

private struct OverviewMonthRow: View {
    let summary: MonthlyReimbursementSummary
    let maxAmount: Double

    var body: some View {
        let ratio = maxAmount > 0 ? summary.totalAmount / maxAmount : 0

        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    monthTitle
                    Spacer()
                    amountText
                    statusCounts
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        monthTitle
                        Spacer()
                        amountText
                    }
                    statusCounts
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppSurface.cardSubtle)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.62))
                        .frame(width: max(8, proxy.size.width * CGFloat(ratio)))
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
    }

    private var monthTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.monthTitle)
                .font(.callout.bold())
            Text("\(summary.projects.count) 单")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var amountText: some View {
        Text(summary.totalAmount.formatted(AppFormatters.currency))
            .font(.headline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var statusCounts: some View {
        HStack(spacing: 8) {
            OverviewStatusCount(title: "待", count: summary.pendingCount, tint: .orange)
            OverviewStatusCount(title: "报", count: summary.reimbursedCount, tint: .blue)
            OverviewStatusCount(title: "发", count: summary.disbursedCount, tint: .green)
        }
    }
}

private struct OverviewStatusCount: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        Text("\(title) \(count)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct OverviewProjectRow: View {
    let project: ReimbursementProject
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ProjectIconBadge(symbol: project.projectSymbol, accent: project.projectAccent, size: 38)
                    projectInfo
                    Spacer()
                    Text(project.totalAmount.formatted(AppFormatters.currency))
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                    StatusBadge(status: project.status)
                }

                HStack(alignment: .top, spacing: 12) {
                    ProjectIconBadge(symbol: project.projectSymbol, accent: project.projectAccent, size: 38)
                    VStack(alignment: .leading, spacing: 8) {
                        projectInfo
                        HStack {
                            Text(project.totalAmount.formatted(AppFormatters.currency))
                                .font(.headline.weight(.semibold))
                                .monospacedDigit()
                            Spacer()
                            StatusBadge(status: project.status)
                        }
                    }
                }
            }
            .padding(12)
            .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
        }
        .buttonStyle(.plain)
    }

    private var projectInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.callout.bold())
                .lineLimit(1)
            Text(projectSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var projectSummary: String {
        let destination = project.destination.isEmpty ? "未填目的地" : project.destination
        let start = project.startDate.formatted(AppFormatters.date)
        if project.hasEndDate {
            return "\(destination) · \(start) - \(project.endDate.formatted(AppFormatters.date))"
        }
        return "\(destination) · \(start) - 至今"
    }
}

private extension ProjectStatus {
    var overviewTint: Color {
        switch self {
        case .pending:
            return .orange
        case .reimbursed:
            return .blue
        case .disbursed:
            return .green
        }
    }
}

private struct ReimbursementStandardsPage: View {
    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = proxy.size.width < 760 ? 14 : 24

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    employeeLevels
                    rulesSummary
                    standardsTable
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 22)
                .frame(maxWidth: 1180, alignment: .leading)
            }
            .background(AppSurface.pageBackground)
        }
        .background(AppSurface.pageBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.clipboard")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.teal)
                .frame(width: 42, height: 42)
                .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("报销标准")
                    .font(.title2.bold())
                Text("按岗位分类、城市级别和费用项目展示差旅报销标准。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var employeeLevels: some View {
        Panel(title: "岗位分类", systemImage: "person.3.fill", accent: .teal) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(EmployeeLevel.allCases) { level in
                    StandardsLevelCard(level: level)
                }
            }
        }
    }

    private var rulesSummary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
            StandardsRuleCard(
                title: "远程交通",
                value: "一至三类：经济舱 / 一等座；四至六类：二等座",
                icon: "train.side.front.car",
                tint: .blue
            )
            StandardsRuleCard(
                title: "总经理",
                value: "住宿、饮食、市内交通按票据据实报销",
                icon: "person.crop.circle.badge.checkmark",
                tint: .purple
            )
            StandardsRuleCard(
                title: "补助口径",
                value: "饮食和市内交通为 50 元/天，按出差天数统计",
                icon: "yensign.circle.fill",
                tint: .green
            )
        }
    }

    private var standardsTable: some View {
        Panel(title: "标准明细", systemImage: "tablecells", accent: .teal) {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    StandardsMatrixHeader()
                    ForEach(CityTier.allCases) { tier in
                        VStack(alignment: .leading, spacing: 0) {
                            StandardsMatrixRow(
                                region: tier.tableTitle,
                                item: "远程交通费",
                                values: EmployeeLevel.allCases.map { TravelStandard.longDistanceTransportText(for: $0) },
                                highlightsRegion: true
                            )
                            StandardsMatrixRow(
                                region: tier.tableTitle,
                                item: "住宿",
                                values: EmployeeLevel.allCases.map { TravelStandard.lodgingText(for: tier, level: $0) }
                            )
                            StandardsMatrixRow(
                                region: tier.tableTitle,
                                item: "饮食",
                                values: EmployeeLevel.allCases.map { TravelStandard.mealText(for: $0) }
                            )
                            StandardsMatrixRow(
                                region: tier.tableTitle,
                                item: "交通",
                                values: EmployeeLevel.allCases.map { TravelStandard.localTransportText(for: $0) }
                            )
                        }
                    }
                }
                .padding(1)
            }
        }
    }
}

private struct StandardsLevelCard: View {
    let level: EmployeeLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(level.classTitle)
                .font(.caption.bold())
                .foregroundStyle(.teal)
            Text(level.roleTitle)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.80)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.teal.opacity(0.18)))
    }
}

private struct StandardsRuleCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.bold())
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
    }
}

private struct StandardsMatrixHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            StandardsTableCell("地区", width: 150, isHeader: true)
            StandardsTableCell("项目", width: 104, isHeader: true)
            ForEach(EmployeeLevel.allCases) { level in
                StandardsTableCell(level.shortTableTitle, width: 138, isHeader: true)
            }
        }
    }
}

private struct StandardsMatrixRow: View {
    let region: String
    let item: String
    let values: [String]
    var highlightsRegion = false

    var body: some View {
        HStack(spacing: 0) {
            StandardsTableCell(region, width: 150, isRegion: highlightsRegion)
            StandardsTableCell(item, width: 104, isItem: true)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                StandardsTableCell(value, width: 138)
            }
        }
    }
}

private struct StandardsTableCell: View {
    let text: String
    let width: CGFloat
    var isHeader = false
    var isRegion = false
    var isItem = false

    init(_ text: String, width: CGFloat, isHeader: Bool = false, isRegion: Bool = false, isItem: Bool = false) {
        self.text = text
        self.width = width
        self.isHeader = isHeader
        self.isRegion = isRegion
        self.isItem = isItem
    }

    var body: some View {
        Text(text)
            .font(isHeader || isItem ? .callout.bold() : .callout)
            .foregroundStyle(isHeader || isItem ? .secondary : .primary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.72)
            .frame(width: width)
            .frame(minHeight: isHeader ? 58 : 50)
            .padding(.horizontal, 8)
            .background(background)
            .border(AppSurface.hairline)
    }

    private var background: Color {
        if isHeader { return AppSurface.cardSubtle }
        if isRegion { return Color.teal.opacity(0.09) }
        if isItem { return AppSurface.cardSubtle }
        return AppSurface.card
    }
}

private extension CityTier {
    var tableTitle: String {
        switch self {
        case .firstTier:
            return "北京/上海/广州/深圳/天津/重庆"
        case .provincialCapital:
            return "省会城市（含青岛/厦门/苏州）"
        case .prefecture:
            return "地级市"
        case .county:
            return "县级市"
        }
    }
}

private extension EmployeeLevel {
    var classTitle: String {
        rawValue.components(separatedBy: " ").first ?? rawValue
    }

    var roleTitle: String {
        let parts = rawValue.components(separatedBy: " ")
        return parts.dropFirst().joined(separator: " ")
    }

    var shortTableTitle: String {
        "\(classTitle)\n\(roleTitle)"
    }
}

private struct AppSettingsView: View {
    @Binding var appearanceMode: AppAppearanceMode
    @Binding var themeAccent: ProjectAccent
    @Binding var showsStageDayInMenuBar: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = proxy.size.width < 760 ? 14 : 24

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(themeAccent.color)
                            .frame(width: 42, height: 42)
                            .background(themeAccent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("系统设置")
                                .font(.title2.bold())
                            Text("调整外观、强调色和菜单栏显示方式，设置会立即保存。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Panel(title: "外观模式", systemImage: "circle.lefthalf.filled", accent: themeAccent.color) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                AppearanceModeOption(
                                    mode: mode,
                                    isSelected: appearanceMode == mode,
                                    accent: themeAccent.color
                                ) {
                                    appearanceMode = mode
                                }
                            }
                        }
                    }

                    Panel(title: "强调色", systemImage: "paintpalette.fill", accent: themeAccent.color) {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ProjectAccent.allCases) { accent in
                                ThemeAccentOption(
                                    accent: accent,
                                    isSelected: themeAccent == accent
                                ) {
                                    themeAccent = accent
                                }
                            }
                        }

                        Text("项目图标颜色仍然可以在每个项目头像上单独调整。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Panel(title: "菜单栏", systemImage: "menubar.rectangle", accent: themeAccent.color) {
                        Toggle(isOn: $showsStageDayInMenuBar) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("显示当前项目第几天")
                                    .font(.callout.bold())
                                Text("有进行中的项目时，菜单栏图标会显示从开始日期算起的天数；关闭后显示默认图标。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(12)
                        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Panel(title: "关于", systemImage: "info.circle.fill", accent: themeAccent.color) {
                        HStack(spacing: 12) {
                            Image(nsImage: NSApp.applicationIconImage)
                                .resizable()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 9))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "差旅报销助手")
                                    .font(.callout.bold())
                                Text("版本 \(appVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 22)
                .frame(maxWidth: 920, alignment: .leading)
            }
            .background(AppSurface.pageBackground)
        }
        .background(AppSurface.pageBackground)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct AppearanceModeOption: View {
    let mode: AppAppearanceMode
    let isSelected: Bool
    let accent: Color
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 11) {
                Image(systemName: mode.icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? accent : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isSelected ? accent.opacity(0.10) : AppSurface.cardSubtle)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                    Text(mode.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accent.opacity(0.09) : AppSurface.cardSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? accent.opacity(0.44) : Color.primary.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .help("切换为\(mode.title)")
    }
}

private struct ThemeAccentOption: View {
    let accent: ProjectAccent
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent.color)
                    .frame(width: 18, height: 18)

                Text(accent.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent.color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accent.color.opacity(0.09) : AppSurface.cardSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? accent.color.opacity(0.45) : Color.primary.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .help("切换为\(accent.title)强调色")
    }
}

private struct SidebarMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppSurface.hairline)
        )
    }
}

private struct ProjectRow: View {
    let project: ReimbursementProject
    let isSelected: Bool

    private var accent: Color {
        project.projectAccent.color
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProjectIconBadge(symbol: project.projectSymbol, accent: project.projectAccent, size: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    StatusDot(status: project.status)
                }

                HStack(spacing: 8) {
                    Label(project.destination.isEmpty ? "未填写地点" : project.destination, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(project.totalAmount.formatted(AppFormatters.currency))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(projectDateRangeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? accent.opacity(0.10) : Color.clear)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? accent : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? accent.opacity(0.24) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var projectDateRangeText: String {
        if project.hasEndDate {
            return "\(project.startDate.formatted(AppFormatters.date)) - \(project.endDate.formatted(AppFormatters.date))"
        }
        return "\(project.startDate.formatted(AppFormatters.date)) - 至今"
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("选择或新建一个报销项目")
                .font(.title3.bold())
            Text("左侧报销清单用于查看待报销、已报销和已发放项目。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    @Binding var project: ReimbursementProject
    @State private var exportMessage: String?
    @State private var isIconPickerPresented = false
    @State private var isProjectInfoPresented = false
    @State private var isReimbursementStandardsPresented = false

    private var generatedProjectCode: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return "IT-\(formatter.string(from: project.createdAt))-\(project.id.uuidString.prefix(4))"
    }

    private var statusSelection: Binding<ProjectStatus> {
        Binding(
            get: { project.status },
            set: { newStatus in
                guard project.status != newStatus else { return }
                project.status = newStatus
                project.settledAt = newStatus == .disbursed ? Date() : nil
                project.updatedAt = Date()
            }
        )
    }

    private var projectPeriodText: String {
        if project.hasEndDate {
            return "\(project.startDate.formatted(AppFormatters.date)) - \(project.endDate.formatted(AppFormatters.date))"
        }
        return "\(project.startDate.formatted(AppFormatters.date)) - 至今"
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = proxy.size.width < 720 ? 14 : 22
            let maxContentWidth: CGFloat = proxy.size.width < 980 ? .infinity : 1280

            VStack(spacing: 0) {
                detailToolbar
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        allowanceForm
                        summaryCards
                        calendarSection
                        travelSegmentsSection
                        expensesSection
                        attachmentsSection
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 14)
                    .frame(maxWidth: maxContentWidth, alignment: .leading)
                }
            }
            .background(AppSurface.pageBackground)
        }
        .background(AppSurface.pageBackground)
        .alert("操作提示", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("知道了", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .sheet(isPresented: $isProjectInfoPresented) {
            ProjectInfoEditor(project: $project)
                .padding(20)
                .frame(width: 560)
        }
        .sheet(isPresented: $isReimbursementStandardsPresented) {
            ReimbursementStandardsEditor(project: $project)
                .padding(20)
                .frame(width: 680)
        }
    }

    private var detailToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Label(project.name, systemImage: "doc.text")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                HeaderMetaPill(icon: "calendar", text: projectPeriodText)

                Spacer()

                toolbarActions(showLabels: true)
            }

            HStack(spacing: 8) {
                Text(project.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                toolbarActions(showLabels: false)
            }
        }
    }

    @ViewBuilder
    private func toolbarActions(showLabels: Bool) -> some View {
        Button {
            chooseInvoices()
        } label: {
            if showLabels {
                Label("导入发票", systemImage: "doc.text.viewfinder")
            } else {
                Image(systemName: "doc.text.viewfinder")
                    .frame(width: 28, height: 26)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(project.projectAccent.color)
        .help("导入发票识别")

        Button {
            store.addTravelSegment(to: project.id)
        } label: {
            if showLabels {
                Label("添加行程", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            } else {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .frame(width: 28, height: 26)
            }
        }
        .buttonStyle(.bordered)
        .help("添加行程")

        Button {
            store.addExpense(to: project.id)
        } label: {
            if showLabels {
                Label("添加费用", systemImage: "plus.rectangle.on.rectangle")
            } else {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .frame(width: 28, height: 26)
            }
        }
        .buttonStyle(.bordered)
        .help("添加费用")

        Button {
            exportPDF()
        } label: {
            if showLabels {
                Label("导出 PDF", systemImage: "square.and.arrow.down")
            } else {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 28, height: 26)
            }
        }
        .buttonStyle(.bordered)
        .help("导出 PDF")
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                projectIconEditor
                projectTitleBlock

                projectTotalBlock(alignment: .trailing)
                    .frame(width: 190, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    projectIconEditor
                    projectTitleBlock
                }

                projectTotalBlock(alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(project.projectAccent.color)
                .frame(width: 4)
                .padding(.vertical, 16)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
        .overlay(alignment: .bottomLeading) {
            if let exportMessage {
                Label(exportMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppSurface.card, in: Capsule())
                    .offset(x: 24, y: 16)
            }
        }
    }

    private var projectIconEditor: some View {
        Button {
            isIconPickerPresented.toggle()
        } label: {
            ProjectIconBadge(symbol: project.projectSymbol, accent: project.projectAccent, size: 52)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.callout)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, project.projectAccent.color)
                        .background(.background, in: Circle())
                }
        }
        .buttonStyle(.plain)
        .help("更换项目图标")
        .popover(isPresented: $isIconPickerPresented, arrowEdge: .bottom) {
            ProjectIconPicker(symbol: $project.projectSymbol, accent: $project.projectAccent)
        }
    }

    private var projectTitleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                TextField("项目名称", text: $project.name)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .frame(maxWidth: 420)

                Button {
                    isProjectInfoPresented = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("编辑项目信息")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    headerStatusControls
                    HeaderMetaPill(icon: "calendar", text: projectPeriodText)
                    HeaderMetaPill(icon: "person", text: project.traveler.isEmpty ? "未填出差人" : project.traveler)
                    HeaderMetaPill(icon: "mappin.and.ellipse", text: project.destination.isEmpty ? "未填目的地" : project.destination)
                    if !project.hasEndDate {
                        HeaderMetaPill(icon: "clock.arrow.circlepath", text: "进行中")
                    }
                }

                HStack(spacing: 8) {
                    headerStatusControls
                    HeaderMetaPill(icon: "calendar", text: projectPeriodText)
                }

                HStack(spacing: 8) {
                    headerStatusControls
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func projectTotalBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text("项目合计")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(project.totalAmount.formatted(AppFormatters.currency))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(project.projectAccent.color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Button {
                store.toggleSettlement(for: project.id)
            } label: {
                Label(project.isSettled ? "取消发放" : "标记已发放", systemImage: project.isSettled ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .tint(project.isSettled ? .gray : .green)
        }
    }

    private var headerStatusControls: some View {
        HStack(spacing: 8) {
            StatusBadge(status: project.status)

            Picker("报销状态", selection: statusSelection) {
                ForEach(ProjectStatus.allCases) { status in
                    Text(status.rawValue).tag(status)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 100)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var detailTabs: some View {
        HStack(spacing: 26) {
            DetailTabButton(title: "报销概览", isSelected: true, accent: project.projectAccent.color)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var tripInfoCard: some View {
        Panel(title: "出差信息", systemImage: "person.crop.circle", accent: project.projectAccent.color) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                GridRow {
                    InfoItem(icon: "person", title: "出差人", value: project.traveler.isEmpty ? "未填写" : project.traveler)
                    InfoItem(icon: "number", title: "行程单号", value: generatedProjectCode)
                }
                GridRow {
                    InfoItem(icon: "mappin.and.ellipse", title: "出差目的地", value: project.destination.isEmpty ? "未填写" : project.destination)
                    InfoItem(icon: "folder", title: "项目", value: project.department.isEmpty ? "未填写" : project.department)
                }
                GridRow {
                    InfoItem(icon: "doc.text", title: "出差事由", value: project.reason.isEmpty ? "未填写" : project.reason)
                    InfoItem(icon: "note.text", title: "备注", value: project.reason.isEmpty ? "未填写" : project.reason)
                }
            }
            HStack {
                Spacer()
                Button {
                    isProjectInfoPresented = true
                } label: {
                    Label("编辑项目信息", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var summaryCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                SummaryStripItem(title: "出差天数", value: String(format: "%.1f 天", project.calculatedTravelDays), icon: "calendar", tint: project.projectAccent.color)
                SummaryDivider()
                SummaryStripItem(title: "补助应发", value: project.allowanceAmount.formatted(AppFormatters.currency), icon: "banknote", tint: .green)
                SummaryDivider()
                SummaryStripItem(title: "票据费用", value: project.expenseTotal.formatted(AppFormatters.currency), icon: "receipt", tint: .orange)
                SummaryDivider()
                SummaryStripItem(title: "项目合计", value: project.totalAmount.formatted(AppFormatters.currency), icon: "shippingbox.fill", tint: .purple)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                SummaryStripItem(title: "出差天数", value: String(format: "%.1f 天", project.calculatedTravelDays), icon: "calendar", tint: project.projectAccent.color)
                SummaryStripItem(title: "补助应发", value: project.allowanceAmount.formatted(AppFormatters.currency), icon: "banknote", tint: .green)
                SummaryStripItem(title: "票据费用", value: project.expenseTotal.formatted(AppFormatters.currency), icon: "receipt", tint: .orange)
                SummaryStripItem(title: "项目合计", value: project.totalAmount.formatted(AppFormatters.currency), icon: "shippingbox.fill", tint: .purple)
            }
        }
        .padding(14)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
    }

    private var calendarSection: some View {
        ProjectCalendarPanel(project: $project, accent: project.projectAccent.color)
    }

    private var allowanceForm: some View {
        Panel(title: "出差时间与补助", systemImage: "clock", accent: .green) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    allowanceInputs

                    Divider()
                        .frame(height: 132)

                    allowanceSummaryBlock
                        .frame(width: 260)
                }

                VStack(alignment: .leading, spacing: 14) {
                    allowanceInputs
                    allowanceSummaryBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onChange(of: project.hasEndDate) { _, isEnabled in
            if isEnabled, project.endDate <= project.startDate {
                project.endDate = Calendar.current.date(byAdding: .hour, value: 9, to: project.startDate) ?? project.startDate
            }
        }
        .onChange(of: project.startDate) { _, newStartDate in
            if project.hasEndDate, project.endDate <= newStartDate {
                project.endDate = Calendar.current.date(byAdding: .hour, value: 9, to: newStartDate) ?? newStartDate
            }
        }
    }

    private var allowanceInputs: some View {
        VStack(alignment: .leading, spacing: 14) {
            allowanceDateControls
            allowanceRateControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allowanceDateControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                startDateControl
                endDateControl
            }

            VStack(alignment: .leading, spacing: 12) {
                startDateControl
                endDateControl
            }
        }
    }

    private var startDateControl: some View {
        AllowanceDateControl(
            title: "开始时间",
            icon: "arrow.up.right.circle",
            selection: $project.startDate,
            isActive: true,
            inactiveText: "",
            accent: .green
        )
    }

    private var endDateControl: some View {
        AllowanceDateControl(
            title: "结束时间",
            icon: "flag.checkered",
            selection: $project.endDate,
            isActive: project.hasEndDate,
            inactiveText: "按今天动态计算",
            accent: .green
        )
    }

    private var allowanceRateControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                allowanceRateField
                Spacer(minLength: 12)
                endDateToggle
            }

            VStack(alignment: .leading, spacing: 12) {
                allowanceRateField
                endDateToggle
            }
        }
    }

    private var allowanceRateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("补助标准")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                DecimalTextField("例如 100", value: $project.allowanceRate)
                    .frame(width: 160)
                Text("元/天")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var endDateToggle: some View {
        Toggle("设置结束时间", isOn: $project.hasEndDate)
            .toggleStyle(.switch)
            .font(.callout.weight(.medium))
    }

    private var allowanceSummaryBlock: some View {
        AllowanceSummary(
            days: String(format: "%.1f 天", project.calculatedTravelDays),
            rate: project.allowanceRate.formatted(AppFormatters.currency),
            amount: project.allowanceAmount.formatted(AppFormatters.currency),
            accent: project.projectAccent.color
        )
    }

    private var expensesSection: some View {
        Panel(title: "费用明细", systemImage: "list.bullet.rectangle", accent: .orange) {
            VStack(spacing: 10) {
                HStack {
                    Text("可录入住宿费、伙食费等额外票据；行程金额在“行程与票据”中录入并自动计入项目合计。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.addExpense(to: project.id)
                    } label: {
                        Label("添加费用", systemImage: "plus")
                    }
                }

                VStack(spacing: 8) {
                    ExpenseHeader()
                    ForEach($project.expenses) { $expense in
                        ExpenseRow(expense: $expense) {
                            project.expenses.removeAll { $0.id == expense.id }
                        }
                    }
                }
            }
        }
    }

    private var travelSegmentsSection: some View {
        Panel(title: "行程与票据", systemImage: "point.topleft.down.curvedto.point.bottomright.up", accent: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("可以手动录入起止地点、时间、出行方式、单程/往返报销和金额；也可以导入发票自动识别。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.addTravelSegment(to: project.id)
                    } label: {
                        Label("添加行程", systemImage: "plus")
                    }

                    Button {
                        chooseInvoices()
                    } label: {
                        Label("导入发票识别", systemImage: "doc.text.viewfinder")
                    }
                }

                if project.travelSegments.isEmpty {
                    ContentUnavailableView("暂无行程", systemImage: "arrow.triangle.swap", description: Text("添加一条行程，或导入高铁、飞机、打车发票进行识别。"))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 10) {
                        ForEach($project.travelSegments) { $segment in
                            TravelSegmentRow(segment: $segment) {
                                project.travelSegments.removeAll { $0.id == segment.id }
                            }
                        }
                    }
                }
            }
        }
    }

    private var attachmentsSection: some View {
        Panel(title: "附件", systemImage: "paperclip", accent: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("仅支持上传 PDF 和截图；导出 PDF 时会按上传顺序追加附件内容。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        chooseInvoices()
                    } label: {
                        Label("导入发票识别", systemImage: "doc.text.viewfinder")
                    }

                    Button {
                        chooseAttachments()
                    } label: {
                        Label("添加附件", systemImage: "plus")
                    }
                }

                if project.attachments.isEmpty {
                    ContentUnavailableView("暂无附件", systemImage: "paperclip", description: Text("添加截图或 PDF 后会保存在本机项目里，并在导出 PDF 时依次展示。"))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                        ForEach(project.attachments) { attachment in
                            AttachmentCard(attachment: attachment) {
                                store.removeAttachment(attachment, from: project.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.title = "选择 PDF 或截图"
        panel.message = "仅支持 PDF 和图片截图。"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image, .png, .jpeg, .heic, .tiff]
        if panel.runModal() == .OK {
            store.importAttachments(panel.urls, to: project.id)
        }
    }

    private func chooseInvoices() {
        let panel = NSOpenPanel()
        panel.title = "导入发票并识别行程"
        panel.message = "支持 PDF 和图片发票。识别结果会写入行程与费用明细，原文件会作为附件保存。"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image, .png, .jpeg, .heic, .tiff]
        if panel.runModal() == .OK {
            store.importInvoices(panel.urls, to: project.id)
        }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.title = "导出报销 PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(project.name)-报销汇总.pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try PDFExporter.export(project: project, to: url)
                exportMessage = "已导出到 \(url.lastPathComponent)"
            } catch {
                store.lastError = "PDF 导出失败：\(error.localizedDescription)"
            }
        }
    }
}

private struct ProjectInfoEditor: View {
    @Binding var project: ReimbursementProject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader(title: "项目信息", subtitle: "这些内容通常只需要维护一次。", icon: "folder", tint: project.projectAccent.color)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    labeledField("出差人", text: $project.traveler)
                    labeledField("费用部门", text: $project.department)
                }
                GridRow {
                    labeledField("出差地点", text: $project.destination)
                    labeledField("事由", text: $project.reason)
                }
            }

            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(project.projectAccent.color)
            }
        }
        .onChange(of: project.destination) { _, newValue in
            guard let tier = TravelStandard.inferredCityTier(from: newValue) else { return }
            project.cityTier = tier
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ReimbursementStandardsEditor: View {
    @Binding var project: ReimbursementProject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader(title: "报销标准提示", subtitle: "按城市类别和岗位类别提示可报销标准。", icon: "building.2.crop.circle", tint: .teal)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("城市类别")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("城市类别", selection: $project.cityTier) {
                            ForEach(CityTier.allCases) { tier in
                                Text(tier.rawValue).tag(tier)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("岗位类别")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("岗位类别", selection: $project.employeeLevel) {
                            ForEach(EmployeeLevel.allCases) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }

            HStack(spacing: 12) {
                StandardCard(title: "住宿标准", value: project.lodgingStandardText, icon: "bed.double")
                StandardCard(title: "饮食标准", value: project.mealStandardText, icon: "fork.knife")
                StandardCard(title: "市内交通", value: project.localTransportStandardText, icon: "car")
            }

            Label(project.longDistanceTransportStandardText, systemImage: "train.side.front.car")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
    }
}

private func sheetHeader(title: String, subtitle: String, icon: String, tint: Color) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusBadge: View {
    let status: ProjectStatus

    var body: some View {
        Label(status.rawValue, systemImage: icon)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .pending:
            return .orange
        case .reimbursed:
            return .blue
        case .disbursed:
            return .green
        }
    }

    private var icon: String {
        switch status {
        case .pending:
            return "clock.fill"
        case .reimbursed:
            return "doc.text.fill"
        case .disbursed:
            return "checkmark.seal.fill"
        }
    }
}

private struct StatusDot: View {
    let status: ProjectStatus

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 9, height: 9)
            .help(status.rawValue)
    }

    private var tint: Color {
        switch status {
        case .pending:
            return .orange
        case .reimbursed:
            return .blue
        case .disbursed:
            return .green
        }
    }
}

private struct ProjectIconBadge: View {
    let symbol: ProjectSymbol
    let accent: ProjectAccent
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(8, size * 0.22))
                .fill(accent.color.opacity(0.14))
            RoundedRectangle(cornerRadius: max(8, size * 0.22))
                .stroke(accent.color.opacity(0.22), lineWidth: 1)
            Image(systemName: symbol.rawValue)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(accent.color)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(symbol.title)
    }
}

private struct HeaderMetaPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AppSurface.cardSubtle, in: Capsule())
            .overlay(Capsule().stroke(AppSurface.hairline))
    }
}

private struct AllowanceDateControl: View {
    let title: String
    let icon: String
    @Binding var selection: Date
    let isActive: Bool
    let inactiveText: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isActive {
                DateInputField(selection: $selection, mode: .dateTime, width: 236)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(inactiveText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(width: 236, height: 34)
                .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppSurface.hairline))
            }
        }
    }
}

private struct AllowanceSummary: View {
    let days: String
    let rate: String
    let amount: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("补助计算")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(amount)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            VStack(spacing: 8) {
                AllowanceSummaryRow(title: "补助天数", value: days)
                AllowanceSummaryRow(title: "每日标准", value: rate)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.16)))
    }
}

private struct AllowanceSummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

private struct HeroPill: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

private struct ToolbarIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .background(AppSurface.card, in: Circle())
        .overlay(Circle().stroke(AppSurface.hairline))
    }
}

private struct DetailTabButton: View {
    let title: String
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? accent : .secondary)
            Rectangle()
                .fill(isSelected ? accent : Color.clear)
                .frame(height: 2)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SummaryStripItem: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }
}

private struct SummaryDivider: View {
    var body: some View {
        Divider()
            .frame(height: 44)
            .padding(.horizontal, 12)
    }
}

private struct InfoItem: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectIconPicker: View {
    @Binding var symbol: ProjectSymbol
    @Binding var accent: ProjectAccent

    private let columns = [
        GridItem(.fixed(44), spacing: 8),
        GridItem(.fixed(44), spacing: 8),
        GridItem(.fixed(44), spacing: 8),
        GridItem(.fixed(44), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("项目图标")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ProjectSymbol.allCases) { item in
                    Button {
                        symbol = item
                    } label: {
                        ProjectIconBadge(symbol: item, accent: accent, size: 42)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(symbol == item ? accent.color : .clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(item.title)
                }
            }

            Divider()

            Text("颜色")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(ProjectAccent.allCases) { item in
                    Button {
                        accent = item
                    } label: {
                        ZStack {
                            Circle()
                                .fill(item.color)
                                .frame(width: 24, height: 24)
                            if accent == item {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(item.title)
                }
            }
        }
        .padding(16)
        .frame(width: 250)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                Spacer()
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppSurface.hairline)
        )
    }
}

private struct StandardCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppSurface.hairline)
        )
    }
}

private struct Panel<Content: View>: View {
    let title: String
    let systemImage: String
    var accent: Color = .blue
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content
        }
        .padding(16)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppSurface.hairline)
        )
    }
}

private struct ProjectCalendarPanel: View {
    @Binding var project: ReimbursementProject
    let accent: Color
    @State private var selectedDate: Date?

    private var calendarRevision: String {
        let segmentDates = project.travelSegments
            .map { "\($0.id.uuidString):\($0.departAt.timeIntervalSinceReferenceDate):\($0.arriveAt.timeIntervalSinceReferenceDate):\($0.amount)" }
            .joined(separator: "|")
        let expenseDates = project.expenses
            .map { "\($0.id.uuidString):\($0.date.timeIntervalSinceReferenceDate):\($0.amount)" }
            .joined(separator: "|")
        return [
            project.id.uuidString,
            "\(project.startDate.timeIntervalSinceReferenceDate)",
            "\(project.endDate.timeIntervalSinceReferenceDate)",
            "\(project.hasEndDate)",
            segmentDates,
            expenseDates
        ].joined(separator: "#")
    }

    var body: some View {
        Panel(title: "日历视角", systemImage: "calendar", accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                CalendarLegend(accent: accent)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 14)],
                    alignment: .center,
                    spacing: 14
                ) {
                    ForEach(CalendarDisplay.months(for: project), id: \.self) { month in
                        CalendarMonthView(
                            month: month,
                            project: project,
                            accent: accent,
                            selectedDate: $selectedDate
                        )
                    }
                }
                .id(calendarRevision)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onAppear {
                if selectedDate == nil {
                    selectedDate = CalendarDisplay.initialSelectedDate(for: project)
                }
            }
            .onChange(of: project.id) { _, _ in
                selectedDate = CalendarDisplay.initialSelectedDate(for: project)
            }
            .onChange(of: calendarRevision) { _, _ in
                selectedDate = CalendarDisplay.initialSelectedDate(for: project)
            }
        }
    }
}

private struct GlobalCalendarView: View {
    let projects: [ReimbursementProject]
    @Environment(\.dismiss) private var dismiss

    private var sortedProjects: [ReimbursementProject] {
        projects.sorted {
            if $0.startDate == $1.startDate {
                return $0.createdAt > $1.createdAt
            }
            return $0.startDate > $1.startDate
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("全日历")
                        .font(.title2.bold())
                    Text("汇总展示所有项目的出差区间、行程和费用日期")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label("关闭", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Divider()

            if projects.isEmpty {
                ContentUnavailableView("暂无出差记录", systemImage: "calendar.badge.exclamationmark", description: Text("新建报销项目后，全日历会自动标记相关日期。"))
                    .frame(width: 860, height: 520)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        GlobalCalendarSummary(projects: sortedProjects)

                        GlobalCalendarLegend()

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                            ForEach(CalendarDisplay.months(for: projects), id: \.self) { month in
                                GlobalCalendarMonthView(month: month, projects: projects)
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(minWidth: 900, minHeight: 620)
                .background(AppSurface.pageBackground)
            }
        }
    }
}

private struct GlobalCalendarSummary: View {
    let projects: [ReimbursementProject]

    private var activeCount: Int {
        projects.filter { !$0.isSettled }.count
    }

    private var travelDayCount: Int {
        var days: Set<Date> = []
        for project in projects {
            CalendarDisplay.projectDays(for: project).forEach { days.insert($0) }
        }
        return days.count
    }

    private var linkedAmount: Double {
        projects.reduce(0) { $0 + $1.expenseTotal }
    }

    var body: some View {
        HStack(spacing: 12) {
            SummaryPill(title: "项目", value: "\(projects.count) 个", icon: "folder.fill", tint: .blue)
            SummaryPill(title: "未发放", value: "\(activeCount) 个", icon: "clock.badge.exclamationmark", tint: .orange)
            SummaryPill(title: "出差日期", value: "\(travelDayCount) 天", icon: "calendar", tint: .green)
            SummaryPill(title: "票据/行程金额", value: linkedAmount.formatted(AppFormatters.currency), icon: "receipt.fill", tint: .purple)
        }
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppSurface.hairline)
        )
    }
}

private struct GlobalCalendarLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.10))
                    .frame(width: 18, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.blue.opacity(0.18))
                    )
                Text("出差区间")
            }
            CalendarLegendDot(title: "有行程", color: .blue)
            CalendarLegendDot(title: "有费用", color: .orange)
            CalendarLegendDot(title: "多个项目", color: .purple)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct GlobalCalendarMonthView: View {
    let month: Date
    let projects: [ReimbursementProject]

    private let weekdayTitles = ["一", "二", "三", "四", "五", "六", "日"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(month.formatted(.dateTime.year().month()))
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(CalendarDisplay.daySlots(in: month)) { slot in
                    if let date = slot.date {
                        GlobalCalendarDayCell(
                            date: date,
                            markers: CalendarDisplay.globalMarkers(on: date, projects: projects)
                        )
                    } else {
                        Color.clear
                            .frame(height: 42)
                    }
                }
            }
        }
        .padding(12)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppSurface.hairline)
        )
    }
}

private struct GlobalCalendarDayCell: View {
    let date: Date
    let markers: GlobalCalendarMarkers

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var hasAnyMarker: Bool {
        markers.hasProjectRange || markers.hasTravel || markers.hasReimbursement
    }

    var body: some View {
        VStack(spacing: 5) {
            Text("\(dayNumber)")
                .font(.callout.weight(isToday ? .semibold : .regular))
                .foregroundStyle(hasAnyMarker ? .primary : .secondary)
                .frame(maxWidth: .infinity)

            HStack(spacing: 3) {
                if markers.hasTravel {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 4.5, height: 4.5)
                }
                if markers.hasReimbursement {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4.5, height: 4.5)
                }
                if markers.projectCount > 1 {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 4.5, height: 4.5)
                }
            }
            .frame(height: 6)
        }
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(markers.hasProjectRange ? Color.blue.opacity(0.075) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(cellBorder, lineWidth: isToday ? 1.4 : 1)
        )
        .help(helpText)
    }

    private var cellBorder: Color {
        if isToday {
            return Color.blue.opacity(0.45)
        }
        if markers.projectCount > 1 {
            return Color.purple.opacity(0.28)
        }
        return .clear
    }

    private var helpText: String {
        var parts = [date.formatted(AppFormatters.date)]
        if markers.projectCount > 0 {
            parts.append("\(markers.projectCount) 个项目")
        }
        if markers.hasTravel {
            parts.append("有行程")
        }
        if markers.hasReimbursement {
            parts.append("有费用")
        }
        return parts.joined(separator: " · ")
    }
}

private struct CalendarLegend: View {
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(accent.opacity(0.12))
                    .frame(width: 18, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(accent.opacity(0.18))
                    )
                Text("出差/补助区间")
            }

            CalendarLegendDot(title: "有行程", color: .blue)
            CalendarLegendDot(title: "有费用", color: .orange)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct CalendarLegendDot: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
    }
}

private struct CalendarMonthView: View {
    let month: Date
    let project: ReimbursementProject
    let accent: Color
    @Binding var selectedDate: Date?

    private let weekdayTitles = ["一", "二", "三", "四", "五", "六", "日"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(month.formatted(.dateTime.year().month()))
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(CalendarDisplay.daySlots(in: month)) { slot in
                    if let date = slot.date {
                        CalendarDayCell(
                            date: date,
                            isSelected: CalendarDisplay.isSameDay(date, selectedDate),
                            isInProjectRange: CalendarDisplay.isProjectDay(date, in: project),
                            hasTravel: CalendarDisplay.hasTravel(on: date, in: project),
                            hasReimbursement: CalendarDisplay.hasReimbursement(on: date, in: project),
                            accent: accent
                        ) {
                            selectedDate = CalendarDisplay.startOfDay(date)
                        }
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
        .padding(12)
        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppSurface.hairline)
        )
        .frame(maxWidth: 420)
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isInProjectRange: Bool
    let hasTravel: Bool
    let hasReimbursement: Bool
    let accent: Color
    let onSelect: () -> Void

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var foregroundColor: Color {
        if isSelected {
            return accent
        }
        return isInProjectRange ? .primary : .secondary
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text("\(dayNumber)")
                    .font(.callout.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 3) {
                    if hasTravel {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 4.5, height: 4.5)
                    }
                    if hasReimbursement {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4.5, height: 4.5)
                    }
                }
                .frame(height: 6)
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(cellBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(cellBorder, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(date.formatted(AppFormatters.date))
    }

    private var cellBackground: Color {
        if isSelected {
            return accent.opacity(0.16)
        }
        if isInProjectRange {
            return accent.opacity(0.075)
        }
        return .clear
    }

    private var cellBorder: Color {
        if isSelected {
            return accent.opacity(0.55)
        }
        if isToday {
            return Color.secondary.opacity(0.30)
        }
        return .clear
    }
}

private struct CalendarDayDetail: View {
    let project: ReimbursementProject
    let date: Date
    let accent: Color

    private var isInProjectRange: Bool {
        CalendarDisplay.isProjectDay(date, in: project)
    }

    private var travelSegments: [TravelSegment] {
        project.travelSegments
            .filter { CalendarDisplay.segment($0, intersects: date) }
            .sorted { $0.departAt < $1.departAt }
    }

    private var expenses: [ExpenseLine] {
        project.expenses
            .filter { CalendarDisplay.isSameDay($0.date, date) }
            .sorted { $0.date < $1.date }
    }

    private var linkedAmount: Double {
        travelSegments.reduce(0) { $0 + $1.amount } + expenses.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Text(date.formatted(AppFormatters.date))
                    .font(.headline)

                if isInProjectRange {
                    Label("出差区间", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.10), in: Capsule())
                }

                Spacer()

                if linkedAmount > 0 {
                    Text("关联金额 \(linkedAmount.formatted(AppFormatters.currency))")
                        .font(.callout.bold())
                        .foregroundStyle(.orange)
                }
            }

            if isInProjectRange {
                CalendarDetailRow(
                    icon: "banknote",
                    tint: .green,
                    title: "出差补助",
                    subtitle: "按项目起止时间自动折算；当前标准 \(project.allowanceRate.formatted(AppFormatters.number)) 元/天",
                    amount: nil
                )
            }

            ForEach(travelSegments) { segment in
                CalendarDetailRow(
                    icon: segment.transportMode == .flight ? "airplane" : segment.transportMode == .taxi ? "car.fill" : "train.side.front.car",
                    tint: .blue,
                    title: "\(segment.transportMode.rawValue) · \(segment.routeText)",
                    subtitle: "\(segment.departAt.formatted(AppFormatters.shortDateTime)) - \(segment.arriveAt.formatted(AppFormatters.shortDateTime)) · \(segment.reimbursementDirection.rawValue)",
                    amount: segment.amount > 0 ? segment.amount : nil
                )
            }

            ForEach(expenses) { expense in
                CalendarDetailRow(
                    icon: "receipt",
                    tint: .orange,
                    title: expense.category.rawValue,
                    subtitle: expense.note.isEmpty ? "未填写说明" : expense.note,
                    amount: expense.amount > 0 ? expense.amount : nil
                )
            }

            if !isInProjectRange && travelSegments.isEmpty && expenses.isEmpty {
                Text("当天暂无出差区间、行程或报销费用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
        .padding(13)
        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppSurface.hairline)
        )
    }
}

private struct CalendarDetailRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let amount: Double?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let amount {
                Text(amount.formatted(AppFormatters.currency))
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
            }
        }
        .padding(10)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum DateInputMode {
    case date
    case dateTime

    var includesTime: Bool {
        self == .dateTime
    }
}

private enum DateInputFormatter {
    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d"
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter
    }()
}

private struct DateInputField: View {
    @Binding var selection: Date
    let mode: DateInputMode
    var width: CGFloat = 190
    @State private var isPresented = false

    private var displayText: String {
        switch mode {
        case .date:
            DateInputFormatter.date.string(from: selection)
        case .dateTime:
            DateInputFormatter.dateTime.string(from: selection)
        }
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(displayText)
                    .font(.callout.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .frame(maxWidth: .infinity, alignment: .center)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: 34)
            .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppSurface.hairline)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DateInputPopover(selection: $selection, mode: mode, isPresented: $isPresented)
                .padding(12)
                .frame(width: 318)
        }
    }
}

private struct DateInputPopover: View {
    @Binding var selection: Date
    let mode: DateInputMode
    @Binding var isPresented: Bool
    @State private var visibleMonth = Date()

    private let calendar = Calendar.current
    private let weekdayTitles = ["一", "二", "三", "四", "五", "六", "日"]
    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    moveMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(visibleMonth.formatted(.dateTime.year().month()))
                    .font(.headline)

                Spacer()

                Button {
                    moveMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 22)
                }

                ForEach(CalendarDisplay.daySlots(in: visibleMonth)) { slot in
                    if let date = slot.date {
                        DateInputDayButton(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selection),
                            isToday: calendar.isDateInToday(date)
                        ) {
                            selectDate(date)
                        }
                    } else {
                        Color.clear
                            .frame(width: 36, height: 32)
                    }
                }
            }

            if mode.includesTime {
                Divider()

                HStack(spacing: 10) {
                    DateInputTimeMenu(title: "时", range: 0..<24, selection: hourBinding)
                    DateInputTimeMenu(title: "分", range: 0..<60, selection: minuteBinding)
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Button("今天") {
                    selection = alignedDate(from: Date())
                    visibleMonth = monthStart(for: selection)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("完成") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            visibleMonth = monthStart(for: selection)
        }
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.hour, from: selection) },
            set: { update(.hour, to: $0) }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.minute, from: selection) },
            set: { update(.minute, to: $0) }
        )
    }

    private func selectDate(_ date: Date) {
        selection = alignedDate(from: date)
        if mode == .date {
            isPresented = false
        }
    }

    private func alignedDate(from date: Date) -> Date {
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        if mode.includesTime {
            let timeComponents = calendar.dateComponents([.hour, .minute], from: selection)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
        } else {
            dateComponents.hour = 0
            dateComponents.minute = 0
        }
        return calendar.date(from: dateComponents) ?? date
    }

    private func update(_ component: Calendar.Component, to value: Int) {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: selection)
        switch component {
        case .hour:
            components.hour = value
        case .minute:
            components.minute = value
        default:
            return
        }
        selection = calendar.date(from: components) ?? selection
    }

    private func moveMonth(_ offset: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
    }

    private func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}

private struct DateInputDayButton: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let onSelect: () -> Void

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    var body: some View {
        Button(action: onSelect) {
            Text("\(dayNumber)")
                .font(.callout.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 36, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(isToday ? 0.08 : 0.001))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isToday && !isSelected ? Color.accentColor.opacity(0.45) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct DateInputTimeMenu: View {
    let title: String
    let range: Range<Int>
    @Binding var selection: Int

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Array(range), id: \.self) { value in
                Text(String(format: "%02d %@", value, title)).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 96)
    }
}

private struct CalendarDaySlot: Identifiable {
    let id: Int
    let date: Date?
}

private struct GlobalCalendarMarkers {
    let projectCount: Int
    let hasProjectRange: Bool
    let hasTravel: Bool
    let hasReimbursement: Bool
}

private enum CalendarDisplay {
    static let calendar = Calendar.current

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date?) -> Bool {
        guard let rhs else { return false }
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func isProjectDay(_ date: Date, in project: ReimbursementProject) -> Bool {
        let day = startOfDay(date)
        let (start, end) = displayBounds(for: project)
        return day >= start && day <= end
    }

    static func segment(_ segment: TravelSegment, intersects date: Date) -> Bool {
        let dayStart = startOfDay(date)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        let segmentStart = Swift.min(segment.departAt, segment.arriveAt)
        let segmentEnd = Swift.max(segment.departAt, segment.arriveAt)
        return segmentStart < nextDay && segmentEnd >= dayStart
    }

    static func hasTravel(on date: Date, in project: ReimbursementProject) -> Bool {
        project.travelSegments.contains { segment($0, intersects: date) }
    }

    static func hasReimbursement(on date: Date, in project: ReimbursementProject) -> Bool {
        project.expenses.contains { expense in
            expense.amount > 0 && calendar.isDate(expense.date, inSameDayAs: date)
        } || project.travelSegments.contains { segment in
            segment.amount > 0 && self.segment(segment, intersects: date)
        }
    }

    static func initialSelectedDate(for project: ReimbursementProject) -> Date {
        let today = Date()
        if isProjectDay(today, in: project) {
            return startOfDay(today)
        }
        return startOfDay(project.startDate)
    }

    static func months(for project: ReimbursementProject) -> [Date] {
        let (displayStart, displayEnd) = displayBounds(for: project)
        var relevantDates = [displayStart, displayEnd]
        relevantDates.append(contentsOf: project.expenses.map(\.date))
        project.travelSegments.forEach { segment in
            relevantDates.append(segment.departAt)
            relevantDates.append(segment.arriveAt)
        }

        guard let earliest = relevantDates.min(),
              let latest = relevantDates.max() else {
            return [monthStart(for: Date())]
        }

        let startMonth = monthStart(for: earliest)
        let endMonth = monthStart(for: latest)
        var months: [Date] = []
        var current = startMonth

        while current <= endMonth && months.count < 36 {
            months.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }

        return months.isEmpty ? [startMonth] : months
    }

    static func months(for projects: [ReimbursementProject]) -> [Date] {
        var relevantDates: [Date] = []
        for project in projects {
            let (displayStart, displayEnd) = displayBounds(for: project)
            relevantDates.append(displayStart)
            relevantDates.append(displayEnd)
            relevantDates.append(contentsOf: project.expenses.map(\.date))
            project.travelSegments.forEach { segment in
                relevantDates.append(segment.departAt)
                relevantDates.append(segment.arriveAt)
            }
        }

        guard let earliest = relevantDates.min(),
              let latest = relevantDates.max() else {
            return [monthStart(for: Date())]
        }

        let startMonth = monthStart(for: earliest)
        let endMonth = monthStart(for: latest)
        var months: [Date] = []
        var current = startMonth

        while current <= endMonth && months.count < 60 {
            months.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }

        return months.isEmpty ? [startMonth] : months
    }

    static func projectDays(for project: ReimbursementProject) -> [Date] {
        let (start, end) = displayBounds(for: project)
        guard start <= end else { return [] }
        var dates: [Date] = []
        var current = start

        while current <= end && dates.count < 370 {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return dates
    }

    private static func displayBounds(for project: ReimbursementProject) -> (start: Date, end: Date) {
        if project.hasEndDate {
            return (
                startOfDay(Swift.min(project.startDate, project.endDate)),
                startOfDay(Swift.max(project.startDate, project.endDate))
            )
        }

        return (startOfDay(project.startDate), startOfDay(Date()))
    }

    static func globalMarkers(on date: Date, projects: [ReimbursementProject]) -> GlobalCalendarMarkers {
        let projectsOnDay = projects.filter { isProjectDay(date, in: $0) }
        let containsTravel = projects.contains { hasTravel(on: date, in: $0) }
        let containsReimbursement = projects.contains { hasReimbursement(on: date, in: $0) }

        return GlobalCalendarMarkers(
            projectCount: projectsOnDay.count,
            hasProjectRange: !projectsOnDay.isEmpty,
            hasTravel: containsTravel,
            hasReimbursement: containsReimbursement
        )
    }

    static func daySlots(in month: Date) -> [CalendarDaySlot] {
        let firstDay = monthStart(for: month)
        guard let dayRange = calendar.range(of: .day, in: .month, for: firstDay) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlankCount = (firstWeekday + 5) % 7
        var slots: [CalendarDaySlot] = []
        var position = 0

        for _ in 0..<leadingBlankCount {
            slots.append(CalendarDaySlot(id: position, date: nil))
            position += 1
        }

        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) else { continue }
            slots.append(CalendarDaySlot(id: position, date: date))
            position += 1
        }

        while slots.count % 7 != 0 {
            slots.append(CalendarDaySlot(id: position, date: nil))
            position += 1
        }

        return slots
    }

    private static func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? startOfDay(date)
    }
}

private extension ProjectAccent {
    var color: Color {
        switch self {
        case .blue:
            Color(nsColor: .systemBlue)
        case .green:
            Color(nsColor: .systemGreen)
        case .teal:
            Color(nsColor: .systemTeal)
        case .orange:
            Color(nsColor: .systemOrange)
        case .red:
            Color(nsColor: .systemRed)
        case .purple:
            Color(nsColor: .systemPurple)
        case .indigo:
            Color(nsColor: .systemIndigo)
        case .gray:
            Color(nsColor: .systemGray)
        }
    }
}

private struct TravelSegmentRow: View {
    @Binding var segment: TravelSegment
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                dateField("出发时间", selection: $segment.departAt)
                dateField("到达时间", selection: $segment.arriveAt)

                VStack(alignment: .leading, spacing: 6) {
                    Text("方式").font(.caption).foregroundStyle(.secondary)
                    Picker("方式", selection: $segment.transportMode) {
                        ForEach(TransportMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("报销").font(.caption).foregroundStyle(.secondary)
                    Picker("报销", selection: $segment.reimbursementDirection) {
                        ForEach(ReimbursementDirection.allCases) { direction in
                            Text(direction.rawValue).tag(direction)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 112)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("金额").font(.caption).foregroundStyle(.secondary)
                    DecimalTextField("0.00", value: $segment.amount)
                        .frame(width: 104)
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .padding(.top, 23)
            }

            HStack(spacing: 10) {
                TextField("出发地", text: $segment.fromPlace)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                TextField("目的地", text: $segment.toPlace)
                    .textFieldStyle(.roundedBorder)
                TextField("备注", text: $segment.note)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)
            }
        }
        .padding(12)
        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppSurface.hairline)
        )
    }

    private func dateField(_ title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            DateInputField(selection: selection, mode: .dateTime, width: 184)
        }
    }
}

private struct ExpenseHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("日期").frame(width: 132, alignment: .leading)
            Text("类别").frame(width: 116, alignment: .leading)
            Text("说明").frame(maxWidth: .infinity, alignment: .leading)
            Text("金额").frame(width: 120, alignment: .leading)
            Text("").frame(width: 28)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    }
}

private struct ExpenseRow: View {
    @Binding var expense: ExpenseLine
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            DateInputField(selection: $expense.date, mode: .date, width: 132)

            Picker("", selection: $expense.category) {
                ForEach(ExpenseCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .labelsHidden()
            .frame(width: 116)

            TextField("例如 武汉到大庆机票", text: $expense.note)
                .textFieldStyle(.roundedBorder)

            DecimalTextField("0.00", value: $expense.amount)
                .frame(width: 120)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .frame(width: 28)
        }
        .padding(10)
        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DecimalTextField: View {
    let placeholder: String
    @Binding var value: Double
    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(_ placeholder: String, value: Binding<Double>) {
        self.placeholder = placeholder
        _value = value
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onAppear {
                text = formatted(value)
            }
            .onChange(of: value) { _, newValue in
                guard !isFocused else { return }
                text = formatted(newValue)
            }
            .onChange(of: text) { _, newText in
                let cleaned = sanitized(newText)
                if cleaned != newText {
                    text = cleaned
                    return
                }
                value = Double(cleaned) ?? 0
            }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    text = editableText(value)
                } else {
                    text = formatted(value)
                }
            }
    }

    private func sanitized(_ input: String) -> String {
        var result = ""
        var hasDecimalPoint = false

        for character in input {
            if character.isNumber {
                result.append(character)
            } else if character == "." || character == "," || character == "，" || character == "。" {
                if !hasDecimalPoint {
                    result.append(".")
                    hasDecimalPoint = true
                }
            }
        }

        return result
    }

    private func formatted(_ number: Double) -> String {
        guard number != 0 else { return "" }
        return editableText(number)
    }

    private func editableText(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: number)) ?? ""
    }
}

private struct AttachmentCard: View {
    let attachment: AttachmentItem
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            AttachmentPreview(attachment: attachment)
                .frame(height: 146)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(AppSurface.hairline)
                )

            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(iconColor)
                    .frame(width: 26, height: 26)
                    .background(iconColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.fileName)
                        .font(.callout.bold())
                        .lineLimit(1)
                    Text("\(attachment.kind.rawValue) · \(attachment.addedAt.formatted(AppFormatters.shortDateTime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(13)
        .background(AppSurface.cardSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppSurface.hairline)
        )
    }

    private var icon: String {
        switch attachment.kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .file: "doc"
        }
    }

    private var iconColor: Color {
        switch attachment.kind {
        case .image: .blue
        case .pdf: .red
        case .file: .secondary
        }
    }
}

private struct AttachmentPreview: View {
    let attachment: AttachmentItem

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppSurface.card)

            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(fallbackColor)
                    Text("无法预览")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var previewImage: NSImage? {
        let url = URL(fileURLWithPath: attachment.storedPath)
        switch attachment.kind {
        case .image:
            return NSImage(contentsOf: url)
        case .pdf:
            return PDFDocument(url: url)?
                .page(at: 0)?
                .thumbnail(of: CGSize(width: 520, height: 320), for: .mediaBox)
        case .file:
            return nil
        }
    }

    private var fallbackIcon: String {
        switch attachment.kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .file: "doc"
        }
    }

    private var fallbackColor: Color {
        switch attachment.kind {
        case .image: .blue
        case .pdf: .red
        case .file: .secondary
        }
    }
}
