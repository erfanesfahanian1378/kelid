import ClipboardKit
import KelidCore
import KelidStorage
import PersianText
import UIKit
import UniformTypeIdentifiers

/// Task 10.7's Share Extension: accepts text, URLs and images shared from
/// other apps, saves each as a clip (`source: .share`), shows a brief
/// confirmation, then completes the request. `NSExtensionPrincipalClass`
/// for the `com.apple.share-services` extension point must be a
/// `UIViewController` subclass — this hosts a small native UI directly
/// rather than a SwiftUI view, since there's no navigation or interaction
/// beyond "here's what got saved."
final class ShareViewController: UIViewController {
    private let log = Log.logger(.app)
    private let statusLabel = UILabel()
    private var database: DatabaseManager?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildUI()
        Task { await handleSharedContent() }
    }

    private func buildUI() {
        statusLabel.text = "Saving to Kelid…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    /// §6.11.2: "Share Extension: resume [the database] on start, suspend
    /// before completing the request."
    private func handleSharedContent() async {
        let paths = ContainerPaths.resolve(fullAccess: true)
        let manager = DatabaseManager(fileURL: paths.databaseURL)
        database = manager
        do {
            try await manager.open()
        } catch {
            log.error("Share Extension database open failed: \(error, privacy: .public)")
            finish(status: "Couldn't save — please try again from the Kelid app.")
            return
        }
        await manager.resume()

        guard let itemProvider = firstAttachment() else {
            finish(status: "Nothing to save.")
            return
        }

        let repository = ClipRepository(database: manager)
        if let text = await loadText(from: itemProvider) {
            await save(text: text, kind: .text, repository: repository)
        } else if let url = await loadURL(from: itemProvider) {
            await save(text: url.absoluteString, kind: .url, repository: repository)
        } else if let imageData = await loadImageData(from: itemProvider) {
            await saveImage(data: imageData, repository: repository)
        } else {
            finish(status: "Kelid can't save this kind of content yet.")
        }
    }

    private func firstAttachment() -> NSItemProvider? {
        (extensionContext?.inputItems as? [NSExtensionItem])?.first?.attachments?.first
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                continuation.resume(returning: (item as? String) ?? (item as? NSString) as String?)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: data)
                } else if let data = item as? Data {
                    continuation.resume(returning: data)
                } else if let image = item as? UIImage {
                    continuation.resume(returning: image.pngData())
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func save(text: String, kind: ClipKind, repository: ClipRepository) async {
        let draft = ClipDraft(
            kind: kind, text: text, searchKey: PersianNormalization.searchKey(text),
            contentHash: ClipClassifier.sha256Hex(PersianNormalization.canonical(text)), charCount: text.count, source: .share
        )
        do {
            _ = try await repository.upsert(draft)
            finish(status: "Saved to Kelid.")
        } catch {
            log.error("Share Extension save failed: \(error, privacy: .public)")
            finish(status: "Couldn't save — please try again.")
        }
    }

    /// Downsampled and written to disk exactly the way
    /// `ClipboardService.captureImage(data:)` already does it for the
    /// keyboard's own image-clip capture (§6.5.8) — duplicated rather than
    /// shared, since that method is `private` to a `@MainActor` class built
    /// around a `PasteboardClient`/`ClipboardMonitor` this extension has no
    /// use for; only the downsample-then-write shape is actually reused
    /// (`ImageDownsampler`/`ClipClassifier` themselves, not that method).
    private func saveImage(data: Data, repository: ClipRepository) async {
        guard let result = await Task.detached(priority: .utility, operation: { ImageDownsampler.downsample(data: data) }).value else {
            finish(status: "Couldn't read that image.")
            return
        }
        let paths = ContainerPaths.resolve(fullAccess: true)
        let hash = ClipClassifier.sha256Hex(data)
        let ext = result.isPNG ? "png" : "jpg"
        let imageFilename = "\(UUID().uuidString).\(ext)"
        let thumbFilename = "\(UUID().uuidString)_thumb.\(ext)"
        do {
            try FileManager.default.createDirectory(at: paths.clipImagesDirectoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: paths.clipThumbsDirectoryURL, withIntermediateDirectories: true)
            try result.imageData.write(to: paths.clipImagesDirectoryURL.appendingPathComponent(imageFilename))
            try result.thumbnailData.write(to: paths.clipThumbsDirectoryURL.appendingPathComponent(thumbFilename))
            let draft = ClipClassifier.draftForImage(hash: hash, imageFile: imageFilename, thumbFile: thumbFilename, source: .share)
            _ = try await repository.upsert(draft)
            finish(status: "Saved to Kelid.")
        } catch {
            log.error("Share Extension image save failed: \(error, privacy: .public)")
            finish(status: "Couldn't save that image.")
        }
    }

    private func finish(status: String) {
        statusLabel.text = status
        Task {
            try? await Task.sleep(for: .seconds(1))
            await database?.suspend()
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
