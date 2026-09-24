import KelidCore
import UIKit

/// Phase 0 placeholder keyboard.
///
/// Proves the extension installs, types, has a working globe key, and that
/// height can be changed at runtime (the base for real resizing in
/// Phase 4). Everything here is thin, throwaway wiring — the real
/// `KeyboardRootView` / `KeyGridView` (KeyboardUI) replace it starting in
/// Phase 2. See PLAN.md §8 Phase 0, task 0.6 and §6.3.4.
final class KeyboardViewController: UIInputViewController {
    private let log = Log.logger(.keyboardExtension)

    private let statusLabel = UILabel()
    private let globeButton = UIButton(type: .system)
    private var heightConstraint: NSLayoutConstraint?
    private var currentHeight: CGFloat = 260

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true
        Log.configure(bundleID: Bundle.main.bundleIdentifier)
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyHeight(currentHeight)
        refreshStatus()
        globeButton.isHidden = !needsInputModeSwitchKey
    }

    override func textDidChange(_: UITextInput?) {
        refreshStatus()
    }

    // MARK: - §6.3.4 height mechanism (Phase 0 validates, Phase 4 finalizes)

    private func applyHeight(_ height: CGFloat) {
        if let constraint = heightConstraint {
            constraint.constant = height
            return
        }
        let constraint = view.heightAnchor.constraint(equalToConstant: height)
        constraint.priority = UILayoutPriority(999) // stays below "required" so it never fights UIView-Encapsulated-Layout-Height
        constraint.isActive = true
        heightConstraint = constraint
    }

    @objc private func increaseHeight() {
        currentHeight = min(currentHeight + 20, 500)
        applyHeight(currentHeight)
    }

    @objc private func decreaseHeight() {
        currentHeight = max(currentHeight - 20, 150)
        applyHeight(currentHeight)
    }

    // MARK: - Status line

    private func refreshStatus() {
        let fullAccess = hasFullAccess ? "✓" : "✗"
        let appGroupRead = appGroupProbeReadable ? "✓" : "✗"
        let iosVersion = UIDevice.current.systemVersion
        statusLabel.text = "FullAccess \(fullAccess) · AppGroup read \(appGroupRead) · iOS \(iosVersion)"
        log.debug("status refreshed: fullAccess=\(fullAccess, privacy: .public) appGroupRead=\(appGroupRead, privacy: .public)")
    }

    /// Reads `app.probe`, written by the companion app (task 0.7), from the
    /// shared App Group `UserDefaults`. This only ever succeeds with Full
    /// Access on (§2.1 C2) — used here purely as an on-device signal, not a
    /// real feature.
    private var appGroupProbeReadable: Bool {
        guard let groupID = Bundle.main.object(forInfoDictionaryKey: "KelidAppGroupID") as? String,
              let defaults = UserDefaults(suiteName: groupID) else { return false }
        return defaults.object(forKey: "app.probe") != nil
    }

    // MARK: - UI

    private func buildUI() {
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1
        statusLabel.adjustsFontSizeToFitWidth = true

        let helloButton = makeButton(title: "سلام") { [weak self] in
            self?.textDocumentProxy.insertText("سلام")
        }
        let englishHelloButton = makeButton(title: "hello") { [weak self] in
            self?.textDocumentProxy.insertText("hello")
        }
        let backspaceButton = makeButton(title: "⌫") { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }
        let typingRow = UIStackView(arrangedSubviews: [helloButton, englishHelloButton, backspaceButton])
        typingRow.axis = .horizontal
        typingRow.distribution = .fillEqually
        typingRow.spacing = 8

        let decreaseButton = makeButton(title: "−20") { [weak self] in self?.decreaseHeight() }
        let increaseButton = makeButton(title: "+20") { [weak self] in self?.increaseHeight() }
        globeButton.setTitle("🌐", for: .normal)
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let heightRow = UIStackView(arrangedSubviews: [decreaseButton, globeButton, increaseButton])
        heightRow.axis = .horizontal
        heightRow.distribution = .fillEqually
        heightRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [statusLabel, typingRow, heightRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
        ])
    }

    /// Small closure-based `UIButton` helper; real key handling (touch
    /// tracking, rollover, popups) arrives with `KeyGridView` in Phase 3.
    private func makeButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 20)
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 6
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}
