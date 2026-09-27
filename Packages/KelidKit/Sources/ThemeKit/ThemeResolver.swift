import Foundation

/// A narrow, `KelidSettings`-free mirror of `AppearanceSettings.ThemeMode`
/// plus the two theme-ID settings it needs (same "caller converts, this
/// module stays independent" pattern `PredictionEngine`'s own settings
/// types already established — see PROGRESS.md decision 49/57). `KeyboardUI`
/// (which depends on both `ThemeKit` and `KelidSettings`) builds this from
/// the real `AppearanceSettings`.
public enum ThemeResolutionMode: Sendable, Equatable {
    case fixed(themeID: String)
    case followSystem(lightThemeID: String, darkThemeID: String)
    case followApp(lightThemeID: String, darkThemeID: String)
}

/// §6.8.3's resolution rules. `isDark` is a plain `Bool` the caller has
/// already derived from whichever trait `mode` cares about — this module
/// doesn't know about `UITraitCollection`/`UIKeyboardAppearance`.
public enum ThemeResolver {
    public static func resolve(mode: ThemeResolutionMode, isDark: Bool, builtIns: BuiltInThemeCatalog, customStore: ThemeStore) -> Theme {
        let id: String = switch mode {
        case let .fixed(themeID): themeID
        case let .followSystem(light, dark): isDark ? dark : light
        case let .followApp(light, dark): isDark ? dark : light
        }
        if let custom = customStore.loadCustomTheme(id: id) {
            return custom
        }
        if let builtIn = builtIns.theme(id: id) {
            return builtIn
        }
        // §6.8.3: "A missing custom theme falls back to kelid.light / kelid.dark."
        let fallbackID = isDark ? "kelid.dark" : "kelid.light"
        return builtIns.theme(id: fallbackID) ?? (isDark ? .fallbackDark : .fallbackLight)
    }
}
