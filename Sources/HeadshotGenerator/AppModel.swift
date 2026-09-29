import AppKit
import HeadshotCore
import SwiftUI
import UniformTypeIdentifiers

enum Mode: String, CaseIterable, Identifiable {
    case headshot = "Headshot"
    case avatars = "Avatars"
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var mode: Mode = .headshot
    @Published var settings = HeadshotSettings() { didSet { scheduleRender() } }
    @Published var circularAvatars = true
    @Published private(set) var original: CGImage?
    @Published private(set) var preview: CGImage?
    @Published private(set) var avatars: [AvatarStyle: CGImage] = [:]
    @Published private(set) var isWorking = false
    @Published private(set) var faceFound = false
    @Published private(set) var maskFound = false
    @Published var errorMessage: String?

    private(set) var sourceURL: URL?
    private var analysis: PhotoAnalysis?
    private var renderTask: Task<Void, Never>?
    private let processor = HeadshotProcessor()
    nonisolated private static let previewSize: CGFloat = 1400
    nonisolated private static let avatarPreviewSize: CGFloat = 480

    var hasPhoto: Bool { analysis != nil }

    // MARK: Loading

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ url: URL) {
        isWorking = true
        errorMessage = nil
        let processor = processor
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let image = try HeadshotProcessor.loadImage(at: url)
                    let analysis = try processor.analyze(image)
                    return (analysis, processor.cgImage(analysis.image, maxDimension: Self.previewSize))
                }.value
                sourceURL = url
                analysis = result.0
                original = result.1
                faceFound = result.0.face != nil
                maskFound = result.0.personMask != nil
                avatars = [:]
                scheduleRender(debounce: false)
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Rendering

    func scheduleRender(debounce: Bool = true) {
        guard let analysis else { return }
        renderTask?.cancel()
        isWorking = true
        let settings = settings
        let processor = processor
        renderTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(120)) }
            if Task.isCancelled { return }
            let (headshot, styled) = await Task.detached(priority: .userInitiated) {
                let headshot = processor.cgImage(processor.render(analysis, settings: settings),
                                                 maxDimension: Self.previewSize)
                var avatarSettings = settings
                avatarSettings.crop = .square
                let base = processor.render(analysis, settings: avatarSettings)
                var styled: [AvatarStyle: CGImage] = [:]
                for style in AvatarStyle.allCases {
                    if Task.isCancelled { break }
                    styled[style] = processor.cgImage(AvatarStyler.apply(style, to: base),
                                                      maxDimension: Self.avatarPreviewSize)
                }
                return (headshot, styled)
            }.value
            if Task.isCancelled { return }
            preview = headshot
            avatars = styled
            isWorking = false
        }
    }

    // MARK: Export

    func exportHeadshot() {
        guard let analysis else { return }
        let settings = settings
        save(suggestedName: baseName + "-headshot.png") { [processor] in
            processor.cgImage(processor.render(analysis, settings: settings))
        }
    }

    func exportAvatar(_ style: AvatarStyle) {
        guard let analysis else { return }
        var avatarSettings = settings
        avatarSettings.crop = .square
        let settings = avatarSettings
        let circular = circularAvatars
        let slug = style.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
        save(suggestedName: "\(baseName)-avatar-\(slug).png") { [processor] in
            var avatar = AvatarStyler.apply(style, to: processor.render(analysis, settings: settings))
            if circular { avatar = AvatarStyler.circular(avatar) }
            return processor.cgImage(avatar)
        }
    }

    private var baseName: String { sourceURL?.deletingPathExtension().lastPathComponent ?? "photo" }

    private func save(suggestedName: String, render: @escaping @Sendable () -> CGImage?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let processor = processor
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    guard let cg = render() else { throw HeadshotError.renderFailed }
                    try processor.write(cg, to: url)
                }.value
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
