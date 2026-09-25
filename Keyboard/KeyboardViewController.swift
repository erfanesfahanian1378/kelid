import InputEngine
import KelidCore
import KelidSettings
import KelidStorage
import UIKit

/// Keyboard extension entry point.
///
/// Phase 0 proved the extension installs, types, has a working globe key,
/// and that height can change at runtime. Phase 1 adds the shared
/// infrastructure every later phase relies on: settings sync, the database
/// lifecycle (open/suspend/resume), the heartbeat, and a diagnostics line —
/// still nothing resembling the real keyboard UI, which arrives with
/// `KeyboardRootView` / `KeyGridView` (KeyboardUI) starting in Phase 2.
/// See PLAN.md §8 Phase 0 task 0.6, Phase 1 tasks 1.6–1.9, and §6.3.4.
final class KeyboardViewController: UIInputViewController {
    private let log = Log.logger(.keyboardExtension)
    private let services = KeyboardServices.shared

    private let diagnosticsLabel = UILabel()
    private let globeButton = UIButton(type: .system)
    private var heightConstraint: NSLayoutConstraint?
    private var currentHeight: CGFloat = 260

    private var settingsObservationToken: DarwinObservationToken?

    /// Freshly wraps `textDocumentProxy` on every access (rule 5.1.5:
    /// `UITextDocumentProxy` only through `TextDocument`). Not stored as a
    /// property, so it can never go stale across a document change —
    /// Phase 3 revisits this once document-identity tracking matters
    /// (§6.4.8's shadow buffer).
    private var currentDocument: TextDocument {
        ProxyTextDocument { self.textDocumentProxy }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Log.configure(bundleID: Bundle.main.bundleIdentifier)
        inputView?.allowsSelfSizing = true
        buildUI()
        observeExtensionLifecycleNotifications()
        settingsObservationToken = DarwinNotifier.shared.observe(.settingsChanged) { [weak self] in
            self?.refreshDiagnostics()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resumeServices()
        applyHeight(currentHeight)
        globeButton.isHidden = !needsInputModeSwitchKey
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        suspendServices()
    }

    override func textWillChange(_: UITextInput?) {
        // Nothing to snapshot yet — Phase 3's shadow buffer captures
        // pre-change state here.
    }

    override func textDidChange(_: UITextInput?) {
        refreshDiagnostics()
    }

    // MARK: - Lifecycle wiring (task 1.6)

    /// `viewWillAppear` and returning from the background both mean "we're
    /// about to be used": refresh Full Access, reload settings (in case the
    /// app changed them while we were away), resume the database, write the
    /// heartbeat, and refresh what's on screen.
    private func resumeServices() {
        services.hasFullAccess = hasFullAccess
        services.settings.load()
        let database = services.database
        Task {
            do {
                try await database.open()
            } catch {
                log.error("database open failed: \(error, privacy: .public)")
            }
            await database.resume()
            services.writeHeartbeat()
            refreshDiagnostics()
        }
    }

    /// `viewDidDisappear` and entering the background both mean the process
    /// may be suspended imminently: flush anything pending, then suspend
    /// the database so it never holds a WAL lock while suspended (§2.1 C14).
    /// Nothing to flush yet in Phase 1 — later phases' write-behind caches
    /// (e.g. the personal model, Phase 9) hook in here.
    private func suspendServices() {
        let database = services.database
        Task {
            await database.suspend()
        }
    }

    private func observeExtensionLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHostDidEnterBackground),
            name: NSNotification.Name.NSExtensionHostDidEnterBackground, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHostWillEnterForeground),
            name: NSNotification.Name.NSExtensionHostWillEnterForeground, object: nil
        )
    }

    @objc private func handleHostDidEnterBackground() {
        suspendServices()
    }

    @objc private func handleHostWillEnterForeground() {
        resumeServices()
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

    // MARK: - Diagnostics line (task 1.8)

    /// Settings `updatedAt`, Full Access, App Group readable, DB state
    /// (open / suspended / unavailable), memory MB — plus `keyPopups`
    /// (task 1.9's temporary debug toggle) so the live-sync manual test has
    /// something visible to watch change.
    private func refreshDiagnostics() {
        Task {
            let dbState = await services.database.state
            let fullAccess = hasFullAccess ? "✓" : "✗"
            let appGroupRead = services.isAppGroupReadable ? "✓" : "✗"
            let settings = services.settings.settings
            let memoryMB = String(format: "%.1f", MemoryProbe.footprintMB())
            let updatedAt = Self.diagnosticsDateFormatter.string(from: settings.updatedAt)
            let keyPopups = settings.general.keyPopups ? "on" : "off"
            diagnosticsLabel.text = """
            FullAccess \(fullAccess) · AppGroup \(appGroupRead) · DB \(Self.describe(dbState)) · mem \(memoryMB) MB
            settings@\(updatedAt) · keyPopups \(keyPopups) · iOS \(UIDevice.current.systemVersion)
            """
            log.debug("diagnostics refreshed")
        }
    }

    private static func describe(_ state: KelidStorage.DatabaseManager.State) -> String {
        switch state {
        case .unavailable: "unavailable"
        case .open: "open"
        case .suspended: "suspended"
        }
    }

    private static let diagnosticsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: - UI

    private func buildUI() {
        diagnosticsLabel.font = .systemFont(ofSize: 10)
        diagnosticsLabel.textAlignment = .center
        diagnosticsLabel.numberOfLines = 2
        diagnosticsLabel.adjustsFontSizeToFitWidth = true

        let helloButton = makeButton(title: "سلام") { [weak self] in
            self?.currentDocument.insertText("سلام")
        }
        let englishHelloButton = makeButton(title: "hello") { [weak self] in
            self?.currentDocument.insertText("hello")
        }
        let backspaceButton = makeButton(title: "⌫") { [weak self] in
            self?.currentDocument.deleteBackward()
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

        let stack = UIStackView(arrangedSubviews: [diagnosticsLabel, typingRow, heightRow])
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
