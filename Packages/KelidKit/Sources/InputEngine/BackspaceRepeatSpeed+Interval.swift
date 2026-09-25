import Foundation
import KelidSettings

/// §6.4.6: "Then every 80ms (normal; slow 120ms, fast 50ms)."
extension BackspaceRepeatSpeed {
    var repeatInterval: TimeInterval {
        switch self {
        case .slow: 0.12
        case .normal: 0.08
        case .fast: 0.05
        }
    }
}
