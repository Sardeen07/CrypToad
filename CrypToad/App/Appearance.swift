import SwiftUI
import UIKit

/// The user's light/dark preference (Settings → Appearance).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// UserDefaults key. Also settable at launch: `-appearance dark`.
    static let key = "appearance"

    /// UI tests get a throwaway store so a test choosing Dark never leaks into the next run.
    static var defaults: UserDefaults {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
            ? UserDefaults(suiteName: "ui-testing") ?? .standard
            : .standard
    }

    private var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Applies the preference to every window, including sheets and alerts. Overriding the
    /// window is more reliable than `preferredColorScheme(nil)`, which doesn't always return
    /// to the system setting after a forced mode.
    @MainActor
    func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
