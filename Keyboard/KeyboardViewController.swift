import InputEngine
import KelidCore
import KelidSettings
import KelidStorage
import KeyboardLayout
import KeyboardUI
import UIKit

/// Keyboard extension entry point.
///
/// Phase 0 proved the extension installs, types, has a working globe key,
/// and that height can change at runtime. Phase 1 added the shared
/// infrastructure every later phase relies on (settings sync, the database
/// lifecycle, the heartbeat). Phase 3 replaces the placeholder typing UI
/// with the real thing: `KeyboardController` owns everything key-grid- and
/// input-related; this type's job shrinks to exactly what only a live
/// `UIInputViewController` can provide — the text document proxy, Full
/// Access, `needsInputModeSwitchKey`, trait changes, and the height
/// constraint (§6.3.4).
final class KeyboardViewController: UIInputViewController {
    private let log = Log.logger(.keyboardExtension)
    private let services = KeyboardServices.shared

    private let debugLabel = UILabel()
    private var heightConstraint: NSLayoutConstraint?

    private var settingsObservationToken: DarwinObservationToken?
    private var controller: KeyboardController?

    /// One stable instance for this view controller's whole lifetime —
    /// see `ProxyTextDocument`'s own doc comment for why identity must be
    /// stable rather than freshly wrapping `textDocumentProxy` per access.
    private lazy var document = ProxyTextDocument(viewController: self)

    override func viewDidLoad() {
        super.viewDidLoad()
        Log.configure(bundleID: Bundle.main.bundleIdentifier)
        inputView?.allowsSelfSizing = true
        buildUI()
        observeExtensionLifecycleNotifications()
        settingsObservationToken = DarwinNotifier.shared.observe(.settingsChanged) { [weak self] in
            // `DarwinNotifier` guarantees delivery on the main thread, but
            // that guarantee isn't visible to the type system since the
            // handler type itself is plain `@Sendable`, not `@MainActor`
            // (same pattern/reasoning as `SettingsStore`'s own use of this
            // API).
            MainActor.assumeIsolated {
                self?.settingsDidChange()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resumeServices()
        let controller = makeControllerIfNeeded()
        controller.needsGlobeKey = needsInputModeSwitchKey
        controller.hasFullAccess = hasFullAccess
        controller.systemAppearance = mapAppearance(traitCollection.userInterfaceStyle)
        controller.fieldTraitsDidChange()
        refreshDebugOverlay()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        suspendServices()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        controller?.viewDidLayoutSubviews()
    }

    /// Deprecated in iOS 17 in favor of `registerForTraitChanges` — kept as
    /// the override for now (still fully functional; deployment target is
    /// exactly 17.0) rather than guess at the newer generic closure API
    /// without a way to verify it here. Follow-up noted in PROGRESS.md.
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        controller?.systemAppearance = mapAppearance(traitCollection.userInterfaceStyle)
        controller?.updateMetrics(currentMetrics())
    }

    override func textWillChange(_: UITextInput?) {
        // Nothing to snapshot yet — Phase 5's undo stack captures pre-change
        // state here.
    }

    override func textDidChange(_: UITextInput?) {
        controller?.textDidChange()
        refreshDebugOverlay()
    }

    // MARK: - Controller wiring (task 3.8)

    private func makeControllerIfNeeded() -> KeyboardController {
        if let controller {
            return controller
        }
        // Captures `document` itself (a `ProxyTextDocument`, which only
        // holds `self` *weakly*) rather than `self` — this closure is
        // stored long-term inside `KeyboardController`, so capturing `self`
        // strongly here would be a reference cycle (this view controller ↔
        // its controller ↔ this closure).
        let document = document
        let newController = KeyboardController(
            settings: services.settings.settings,
            metrics: currentMetrics(),
            documentProvider: { document }
        )
        newController.onNextInputMode = { [weak self] in self?.advanceToNextInputMode() }
        newController.onDismissKeyboard = { [weak self] in self?.dismissKeyboard() }
        newController.onHeightChanged = { [weak self] height in self?.applyHeight(height) }
        controller = newController
        installRootView(newController.rootView)
        return newController
    }

    private func installRootView(_ rootView: KeyboardRootView) {
        rootView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(rootView, at: 0)
        NSLayoutConstraint.activate([
            rootView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootView.topAnchor.constraint(equalTo: view.topAnchor),
            rootView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func settingsDidChange() {
        services.settings.load()
        controller?.updateSettings(services.settings.settings)
        refreshDebugOverlay()
    }

    // MARK: - Geometry/appearance mapping (only the host view controller has these)

    private func currentMetrics() -> KeyboardMetrics {
        let orientation: SizeOrientation = traitCollection.verticalSizeClass == .compact ? .landscape : .portrait
        return KeyboardMetrics(sizeProfile: services.settings.sizeProfile(for: orientation))
    }

    private func mapAppearance(_ style: UIUserInterfaceStyle) -> UIKeyboardAppearance {
        style == .dark ? .dark : .light
    }

    // MARK: - Lifecycle wiring (task 1.6)

    /// `viewWillAppear` and returning from the background both mean "we're
    /// about to be used": refresh Full Access, reload settings (in case the
    /// app changed them while we were away), resume the database, write the
    /// heartbeat, and refresh what's on screen.
    private func resumeServices() {
        services.hasFullAccess = hasFullAccess
        services.settings.load()
        controller?.updateSettings(services.settings.settings)
        let database = services.database
        Task {
            do {
                try await database.open()
            } catch {
                log.error("database open failed: \(error, privacy: .public)")
            }
            await database.resume()
            services.writeHeartbeat()
            refreshDebugOverlay()
        }
    }

    /// `viewDidDisappear` and entering the background both mean the process
    /// may be suspended imminently: flush anything pending, then suspend
    /// the database so it never holds a WAL lock while suspended (§2.1 C14).
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

    // MARK: - §6.3.4 height mechanism

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

    // MARK: - Debug overlay (task 3.18, `AdvancedSettings.debugOverlay`)

    private func buildUI() {
        debugLabel.font = .systemFont(ofSize: 9)
        debugLabel.textAlignment = .center
        debugLabel.numberOfLines = 1
        debugLabel.adjustsFontSizeToFitWidth = true
        debugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        debugLabel.textColor = .white
        debugLabel.isHidden = true
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugLabel)
        NSLayoutConstraint.activate([
            debugLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            debugLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            debugLabel.topAnchor.constraint(equalTo: view.topAnchor),
            debugLabel.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    private func refreshDebugOverlay() {
        let enabled = services.settings.settings.advanced.debugOverlay
        debugLabel.isHidden = !enabled
        guard enabled else { return }
        Task {
            let dbState = await services.database.state
            let fullAccess = hasFullAccess ? "✓" : "✗"
            let memoryMB = String(format: "%.1f", MemoryProbe.footprintMB())
            debugLabel.text = "FA \(fullAccess) · DB \(Self.describe(dbState)) · mem \(memoryMB)MB · iOS \(UIDevice.current.systemVersion)"
        }
    }

    private static func describe(_ state: KelidStorage.DatabaseManager.State) -> String {
        switch state {
        case .unavailable: "unavailable"
        case .open: "open"
        case .suspended: "suspended"
        }
    }
}
