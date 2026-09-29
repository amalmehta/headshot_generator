import AppKit
import SwiftUI

/// Appends feedback to a local JSON Lines file; nothing leaves the Mac.
enum FeedbackStore {
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HeadshotGenerator", isDirectory: true)
        return dir.appendingPathComponent("feedback.jsonl")
    }

    static func save(_ text: String) throws {
        let url = fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entry = ["date": ISO8601DateFormatter().string(from: Date()), "feedback": text]
        var line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }
}

/// The small "Feedback" tab pinned to the window's bottom-right corner.
struct FeedbackTab: View {
    @State private var open = false
    @State private var text = ""
    @State private var status: String?

    var body: some View {
        Button { open.toggle() } label: {
            Label("Feedback", systemImage: "bubble.left")
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Send feedback")
        .popover(isPresented: $open, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Feedback").font(.headline)
                TextEditor(text: $text)
                    .font(.body)
                    .frame(width: 300, height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Show file") { NSWorkspace.shared.activateFileViewerSelecting([FeedbackStore.fileURL]) }
                        .disabled(!FileManager.default.fileExists(atPath: FeedbackStore.fileURL.path))
                    Spacer()
                    Button("Save") {
                        do {
                            try FeedbackStore.save(text)
                            text = ""
                            status = "Saved — thank you."
                        } catch {
                            status = error.localizedDescription
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
        }
    }
}
