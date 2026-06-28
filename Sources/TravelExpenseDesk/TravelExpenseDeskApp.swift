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
                .frame(minWidth: 940, minHeight: 660)
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
            Self.prepareMainWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Self.prepareMainWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Self.prepareMainWindow()
        }
    }

    @MainActor
    private static func prepareMainWindow() {
        guard let window = mainWindow else { return }
        keepWindowOnScreen(window)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private static func keepWindowOnScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        var frame = window.frame

        if frame.width > visibleFrame.width {
            frame.size.width = visibleFrame.width
        }
        if frame.height > visibleFrame.height {
            frame.size.height = visibleFrame.height
        }

        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)

        if frame != window.frame {
            window.setFrame(frame, display: true)
        }
    }

    @MainActor
    private static var mainWindow: NSWindow? {
        let candidates = NSApp.windows.filter { window in
            !window.isMiniaturized && window.canBecomeKey
        }

        if let titledWindow = candidates.first(where: { $0.title == "差旅报销助手" }) {
            return titledWindow
        }

        return candidates.first { window in
            window.isVisible && window.contentViewController != nil
        }
    }
}
