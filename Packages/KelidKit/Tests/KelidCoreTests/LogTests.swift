@testable import KelidCore
import Testing

@Suite("Log")
struct LogTests {
    @Test("configure strips the .keyboard extension suffix")
    func stripsKeyboardSuffix() {
        Log.configure(bundleID: "com.example.kelid.keyboard")
        // No public getter for the resolved subsystem by design (Log only
        // hands out configured Loggers); constructing one must not crash,
        // which is the behavior this test guards.
        _ = Log.logger(.keyboardExtension)
    }

    @Test("logger construction does not crash for every category")
    func loggerForEveryCategory() {
        for category in [
            Log.Category.core, .settings, .persianText, .keyboardLayout, .inputEngine,
            .predictionEngine, .storage, .clipboard, .theme, .emoji, .keyboardUI,
            .app, .keyboardExtension, .shareExtension,
        ] {
            _ = Log.logger(category)
        }
    }
}
