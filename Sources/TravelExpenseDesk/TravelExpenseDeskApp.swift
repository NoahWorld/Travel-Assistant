import AppKit
import SwiftUI

@main
struct TravelExpenseDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup("差旅报销助手", id: "main") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.appAppearanceMode.colorScheme)
                .frame(minWidth: 1120, minHeight: 740)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建报销项目") {
                    store.createProject()
                }
                .keyboardShortcut("n")

                Button("删除当前项目") {
                    store.requestDeleteSelectedProject()
                }
                .keyboardShortcut(.delete)
                .disabled(store.selectedProjectID == nil)
            }
        }

        MenuBarExtra {
            QuickExpenseMenuView()
                .environmentObject(store)
                .preferredColorScheme(store.appAppearanceMode.colorScheme)
        } label: {
            if store.showsStageDayInMenuBar, let day = store.currentStageDay {
                Text("\(day)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .help("当前出差第 \(day) 天")
            } else {
                Image(systemName: "yensign.circle.fill")
                    .help("快捷记账")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        bringMainWindowForward()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringMainWindowForward()
        return true
    }

    private func bringMainWindowForward() {
        DispatchQueue.main.async {
            Self.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Self.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    private static var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            window.title == "差旅报销助手" || window.contentViewController != nil
        }
    }
}
