import SwiftUI

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            "浅色模式"
        case .dark:
            "深色模式"
        case .system:
            "跟随系统"
        }
    }

    var summary: String {
        switch self {
        case .light:
            "界面始终使用浅色外观"
        case .dark:
            "界面始终使用深色外观"
        case .system:
            "跟随 macOS 外观设置"
        }
    }

    var icon: String {
        switch self {
        case .light:
            "sun.max.fill"
        case .dark:
            "moon.fill"
        case .system:
            "circle.lefthalf.filled"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            .light
        case .dark:
            .dark
        case .system:
            nil
        }
    }
}
