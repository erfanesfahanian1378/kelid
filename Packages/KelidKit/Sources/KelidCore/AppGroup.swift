import Foundation

/// Reads the App Group identifier every Kelid target shares (PLAN.md §4.1,
/// `group.<prefix>.kelid`). Every target that needs it (`Kelid`,
/// `KelidKeyboard`, later `KelidShare`) sets the `KelidAppGroupID` Info.plist
/// key via `project.yml`, from the `KELID_APP_GROUP` build setting.
public enum AppGroup {
    /// `nil` when the key is missing (e.g. a macOS unit test host with no
    /// such Info.plist entry) — callers fall back to a local container in
    /// that case (see `ContainerPaths`), never crash.
    public static var identifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "KelidAppGroupID") as? String
    }
}
