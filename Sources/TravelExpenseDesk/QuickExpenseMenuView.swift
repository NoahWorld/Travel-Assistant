import SwiftUI

private enum QuickExpenseKind: String, CaseIterable, Identifiable {
    case taxi = "打车"
    case meal = "吃饭"
    case ticket = "购票"
    case lodging = "住宿"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .taxi:
            "car.fill"
        case .meal:
            "fork.knife"
        case .ticket:
            "ticket.fill"
        case .lodging:
            "bed.double.fill"
        }
    }

    var category: ExpenseCategory {
        switch self {
        case .taxi, .ticket:
            .transportation
        case .meal:
            .meal
        case .lodging:
            .accommodation
        }
    }

    var defaultNote: String { rawValue }
}

struct QuickExpenseMenuView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedProjectID: UUID?
    @State private var selectedKind: QuickExpenseKind = .taxi
    @State private var date = Date()
    @State private var amountText = ""
    @State private var note = ""
    @State private var savedMessage = ""

    private var amount: Double? {
        let normalized = amountText
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    private var targetProjectID: UUID? {
        selectedProjectID ?? store.selectedProjectID ?? store.projects.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if store.projects.isEmpty {
                ContentUnavailableView("暂无报销项目", systemImage: "folder.badge.plus", description: Text("先新建一个项目，再记录今日花销。"))
                    .frame(width: 340, height: 180)
                appActions
            } else {
                projectPicker
                kindSelector
                entryFields
                footer
                Divider()
                appActions
            }
        }
        .padding(18)
        .frame(width: 380)
        .onAppear {
            selectedProjectID = targetProjectID
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.14))
                Image(systemName: "yensign.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("今日快捷记账")
                    .font(.headline)
                Text("打车、吃饭、购票等费用会写入当前报销项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("报销项目")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { selectedProjectID ?? store.selectedProjectID ?? store.projects.first?.id },
                set: { selectedProjectID = $0 }
            )) {
                ForEach(store.projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var kindSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("类型")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(QuickExpenseKind.allCases) { kind in
                    Button {
                        selectedKind = kind
                        if note.isEmpty {
                            note = kind.defaultNote
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 17, weight: .semibold))
                            Text(kind.rawValue)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedKind == kind ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedKind == kind ? Color.green : Color.secondary.opacity(0.10))
                    )
                }
            }
        }
    }

    private var entryFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text("日期")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("金额")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $amountText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            GridRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text("备注")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("例如 机场打车、晚餐、高铁票", text: $note)
                        .textFieldStyle(.roundedBorder)
                }
                .gridCellColumns(2)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(savedMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("清空") {
                amountText = ""
                note = ""
                savedMessage = ""
            }
            .buttonStyle(.borderless)

            Button {
                saveExpense()
            } label: {
                Label("记一笔", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled((amount ?? 0) <= 0 || targetProjectID == nil)
        }
    }

    private var appActions: some View {
        HStack(spacing: 8) {
            Spacer()

            Button {
                openMainWindow()
            } label: {
                Image(systemName: "macwindow")
                    .font(.headline)
                    .frame(width: 34, height: 30)
            }
            .help("打开客户端")

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.headline)
                    .frame(width: 34, height: 30)
            }
            .help("退出客户端")
        }
        .buttonStyle(.bordered)
    }

    private func saveExpense() {
        guard let amount, amount > 0 else { return }
        let finalNote = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedKind.defaultNote : note
        store.addQuickExpense(
            to: targetProjectID,
            date: date,
            category: selectedKind.category,
            note: finalNote,
            amount: amount
        )
        amountText = ""
        note = ""
        savedMessage = "已记录 \(selectedKind.rawValue) ¥\(String(format: "%.2f", amount))"
    }

    private func openMainWindow() {
        openWindow(id: "main")
        DispatchQueue.main.async {
            Self.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Self.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            window.title == "差旅报销助手" || window.contentViewController != nil
        }
    }
}
