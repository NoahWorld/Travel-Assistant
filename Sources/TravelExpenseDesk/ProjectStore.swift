import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    private static let themeAccentKey = "TravelExpenseDesk.themeAccent"
    private static let appearanceModeKey = "TravelExpenseDesk.appearanceMode"
    private static let menuBarStageDayKey = "TravelExpenseDesk.menuBarStageDay"
    private let persistenceWriter = ProjectPersistenceWriter()
    private var pendingSaveTask: Task<Void, Never>?
    private var isLoading = false

    @Published var projects: [ReimbursementProject] = [] {
        didSet { scheduleSave() }
    }

    @Published var appAppearanceMode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(appAppearanceMode.rawValue, forKey: Self.appearanceModeKey)
        }
    }

    @Published var appThemeAccent: ProjectAccent {
        didSet {
            UserDefaults.standard.set(appThemeAccent.rawValue, forKey: Self.themeAccentKey)
        }
    }

    @Published var showsStageDayInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showsStageDayInMenuBar, forKey: Self.menuBarStageDayKey)
        }
    }

    @Published var selectedProjectID: ReimbursementProject.ID?
    @Published var lastError: String?
    @Published var projectPendingDeletionID: ReimbursementProject.ID?

    init() {
        let storedAccent = UserDefaults.standard.string(forKey: Self.themeAccentKey)
            .flatMap(ProjectAccent.init(rawValue:))
        let storedAppearance = UserDefaults.standard.string(forKey: Self.appearanceModeKey)
            .flatMap(AppAppearanceMode.init(rawValue:))
        appAppearanceMode = storedAppearance ?? .light
        appThemeAccent = storedAccent ?? .blue
        showsStageDayInMenuBar = UserDefaults.standard.object(forKey: Self.menuBarStageDayKey) as? Bool ?? true

        load()
        normalizeImportedSegments()
        if projects.isEmpty {
            createProject(select: true)
        } else {
            selectedProjectID = projects.first?.id
        }
    }

    var unpaidTotal: Double {
        projects
            .filter { !$0.isSettled }
            .reduce(0) { $0 + $1.totalAmount }
    }

    var settledTotal: Double {
        projects
            .filter(\.isSettled)
            .reduce(0) { $0 + $1.totalAmount }
    }

    var unpaidCount: Int {
        projects.filter { !$0.isSettled }.count
    }

    var currentStageDay: Int? {
        guard let activeProject = currentStageProject else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: activeProject.startDate)
        guard let day = calendar.dateComponents([.day], from: start, to: today).day, day >= 0 else {
            return nil
        }
        return day + 1
    }

    private var currentStageProject: ReimbursementProject? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let candidates = projects.filter { project in
            guard !project.isSettled else { return false }
            let start = calendar.startOfDay(for: project.startDate)
            guard start <= today else { return false }
            guard project.hasEndDate else { return true }
            let end = calendar.startOfDay(for: project.endDate)
            return today <= end
        }

        if let selectedProjectID,
           let selected = candidates.first(where: { $0.id == selectedProjectID }) {
            return selected
        }

        return candidates.sorted { $0.startDate > $1.startDate }.first
    }

    func createProject(select: Bool = true) {
        let month = Calendar.current.component(.month, from: Date())
        var project = ReimbursementProject.blank(named: "\(month)月出差报销")
        project.projectAccent = appThemeAccent
        project.expenses = [
            ExpenseLine(category: .transportation, note: "交通票据", amount: 0)
        ]
        projects.insert(project, at: 0)
        if select {
            selectedProjectID = project.id
        }
    }

    func deleteSelectedProject() {
        guard let selectedProjectID else { return }
        deleteProject(id: selectedProjectID)
    }

    func requestDeleteSelectedProject() {
        guard let selectedProjectID else { return }
        projectPendingDeletionID = selectedProjectID
    }

    func confirmPendingProjectDeletion() {
        guard let projectPendingDeletionID else { return }
        deleteProject(id: projectPendingDeletionID)
        self.projectPendingDeletionID = nil
    }

    private func deleteProject(id: ReimbursementProject.ID) {
        if let project = projects.first(where: { $0.id == id }) {
            project.attachments.forEach { AttachmentManager.remove($0) }
        }
        projects.removeAll { $0.id == id }
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id
        }
    }

    func toggleSettlement(for projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        if projects[index].status == .disbursed {
            projects[index].status = .reimbursed
            projects[index].settledAt = nil
        } else {
            projects[index].status = .disbursed
            projects[index].settledAt = Date()
        }
        projects[index].updatedAt = Date()
    }

    func addExpense(to projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].expenses.append(ExpenseLine())
        projects[index].updatedAt = Date()
    }

    func addQuickExpense(to projectID: UUID?, date: Date = Date(), category: ExpenseCategory, note: String, amount: Double) {
        let fallbackID = selectedProjectID ?? projects.first?.id
        guard let targetID = projectID ?? fallbackID,
              let index = projects.firstIndex(where: { $0.id == targetID }) else { return }

        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        projects[index].expenses.append(
            ExpenseLine(
                date: date,
                category: category,
                note: cleanNote.isEmpty ? category.rawValue : cleanNote,
                amount: amount
            )
        )
        projects[index].updatedAt = Date()
        selectedProjectID = projects[index].id
    }

    func addTravelSegment(to projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }

        var segment = TravelSegment()
        segment.departAt = projects[index].startDate
        segment.arriveAt = projects[index].displayEndDate
        segment.toPlace = projects[index].destination
        projects[index].travelSegments.append(segment)
        projects[index].updatedAt = Date()
    }

    func deleteExpenses(at offsets: IndexSet, from projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        for offset in offsets.sorted(by: >) {
            projects[index].expenses.remove(at: offset)
        }
        projects[index].updatedAt = Date()
    }

    func importAttachments(_ urls: [URL], to projectID: UUID) {
        do {
            let attachments = try AttachmentManager.copyAttachments(from: urls, projectID: projectID)
            guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
            projects[index].attachments.append(contentsOf: attachments)
            projects[index].updatedAt = Date()
        } catch {
            lastError = "附件导入失败：\(error.localizedDescription)"
        }
    }

    func importInvoices(_ urls: [URL], to projectID: UUID) {
        do {
            let attachments = try AttachmentManager.copyAttachments(from: urls, projectID: projectID)
            let result = InvoiceImporter.parse(attachments: attachments)

            guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
            let hadTravelSegments = !projects[index].travelSegments.isEmpty
            projects[index].attachments.append(contentsOf: attachments)
            projects[index].travelSegments.append(contentsOf: result.segments)
            let mergedDuplicatesSkipped = normalizeImportedSegments(at: index)

            if let firstSegment = result.segments.first {
                let earliest = result.segments.map(\.departAt).min() ?? firstSegment.departAt
                let latest = result.segments.map(\.arriveAt).max() ?? firstSegment.arriveAt
                if hadTravelSegments {
                    projects[index].startDate = min(projects[index].startDate, earliest)
                    projects[index].endDate = max(projects[index].endDate, latest)
                } else {
                    projects[index].startDate = earliest
                    projects[index].endDate = latest
                }
                projects[index].hasEndDate = true
                if projects[index].destination.isEmpty {
                    projects[index].destination = firstSegment.toPlace
                }
                if let inferredTier = TravelStandard.inferredCityTier(from: firstSegment.toPlace) {
                    projects[index].cityTier = inferredTier
                }
            }

            projects[index].updatedAt = Date()
            if result.recognizedFiles > 0 {
                let skippedCount = result.duplicatesSkipped + mergedDuplicatesSkipped
                let duplicateText = skippedCount > 0 ? "，已自动去重 \(skippedCount) 条重复票据" : ""
                lastError = "已导入 \(attachments.count) 个附件，并识别出 \(result.segments.count) 条行程\(duplicateText)。"
            } else {
                lastError = "附件已导入，但没有识别出明确行程。可以在“行程与票据”里手动补充起止地点、时间和金额。"
            }
        } catch {
            lastError = "发票导入失败：\(error.localizedDescription)"
        }
    }

    func removeAttachment(_ attachment: AttachmentItem, from projectID: UUID) {
        AttachmentManager.remove(attachment)
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].attachments.removeAll { $0.id == attachment.id }
        projects[index].travelSegments.removeAll { $0.sourceAttachmentID == attachment.id }
        projects[index].updatedAt = Date()
    }

    func save() {
        persistCurrentProjects(after: nil)
    }

    private func load() {
        do {
            let url = try AttachmentManager.dataFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            isLoading = true
            defer { isLoading = false }
            projects = try decoder.decode([ReimbursementProject].self, from: data)
        } catch {
            isLoading = false
            lastError = "读取历史失败：\(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        guard !isLoading else { return }
        persistCurrentProjects(after: 300_000_000)
    }

    private func persistCurrentProjects(after delay: UInt64?) {
        guard !isLoading else { return }
        let snapshot = projects
        let writer = persistenceWriter

        pendingSaveTask?.cancel()
        pendingSaveTask = Task.detached(priority: .utility) { [weak self, snapshot, writer] in
            do {
                if let delay {
                    try await Task.sleep(nanoseconds: delay)
                    try Task.checkCancellation()
                }
                try await writer.write(snapshot)
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.lastError = "保存失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func normalizeImportedSegments() {
        var removedCount = 0
        for index in projects.indices {
            removedCount += normalizeImportedSegments(at: index)
        }

        if removedCount > 0 {
            save()
        }
    }

    @discardableResult
    private func normalizeImportedSegments(at index: Int) -> Int {
        guard projects.indices.contains(index) else { return 0 }

        let attachmentsByID = Dictionary(uniqueKeysWithValues: projects[index].attachments.map { ($0.id, $0) })
        let originalSegments = projects[index].travelSegments
        let deduplicatedSegments = TravelSegmentDeduplicator.deduplicated(originalSegments, attachmentsByID: attachmentsByID)
        let removedCount = originalSegments.count - deduplicatedSegments.count

        if removedCount > 0 {
            projects[index].travelSegments = deduplicatedSegments
            projects[index].updatedAt = Date()
        }

        return removedCount
    }
}

private actor ProjectPersistenceWriter {
    func write(_ projects: [ReimbursementProject]) throws {
        let url = try AttachmentManager.dataFileURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(projects)
        try data.write(to: url, options: .atomic)
    }
}
