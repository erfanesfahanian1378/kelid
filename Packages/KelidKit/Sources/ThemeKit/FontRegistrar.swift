import CoreText
import Foundation

/// §6.8.4: "Bundle Vazirmatn ... Register at process start with
/// `CTFontManagerRegisterFontsForURL(url, .process, nil)`." `CoreText`, not
/// `UIKit` — this stays callable from a UIKit-free module and from both the
/// app and keyboard extension processes (each is a separate process, so
/// each must register the fonts itself; `.process` scope doesn't cross
/// process boundaries).
public enum FontRegistrar {
    /// Registers Vazirmatn Regular and Medium exactly once per process.
    /// Safe to call more than once (`CTFontManagerRegisterFontsForURL`
    /// itself reports — and this silently ignores — a duplicate-registration
    /// error), so callers don't need their own "already registered" guard.
    public static func registerVazirmatn(bundle: Bundle? = nil) {
        let resolvedBundle = bundle ?? .module
        for name in ["Vazirmatn-Regular", "Vazirmatn-Medium"] {
            guard let url = resolvedBundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
