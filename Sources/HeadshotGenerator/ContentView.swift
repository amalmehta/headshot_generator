import HeadshotCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showOriginal = false
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            canvas
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) { FeedbackTab().padding(.trailing, 16) }
            Divider()
            inspector.frame(width: 290)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.openPanel() } label: { Label("Open…", systemImage: "photo.badge.plus") }
                    .keyboardShortcut("o")
            }
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $model.mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.exportHeadshot() } label: { Label("Export Headshot…", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e")
                    .disabled(!model.hasPhoto)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil },
                                                             set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(model.errorMessage ?? "") }
    }

    // MARK: Canvas

    @ViewBuilder private var canvas: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if !model.hasPhoto {
                dropZone
            } else if model.mode == .headshot {
                headshotCanvas
            } else {
                AvatarGallery()
            }
            if model.isWorking {
                ProgressView().controlSize(.small).padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.square").font(.system(size: 56, weight: .thin))
            Text("Drop a photo here").font(.title3)
            Button("Choose a Photo…") { model.openPanel() }
            Text("Everything is processed on this Mac.").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
        .padding(48)
        .background(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4)))
    }

    private var headshotCanvas: some View {
        VStack(spacing: 12) {
            if let image = showOriginal ? model.original : (model.preview ?? model.original) {
                Image(decorative: image, scale: 1)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 8, y: 2)
            }
            Picker("", selection: $showOriginal) {
                Text("Before").tag(true)
                Text("After").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 160)
        }
        .padding(28)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url { Task { @MainActor in model.load(url) } }
        }
        return true
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        Form {
            if model.hasPhoto {
                Section {
                    status(model.faceFound, "Face found", "No face found — centre crop")
                    status(model.maskFound, "Person outlined", "No person mask — background unchanged")
                }
            }
            if model.mode == .headshot { headshotControls } else { avatarControls }
        }
        .formStyle(.grouped)
        .disabled(!model.hasPhoto)
    }

    private func status(_ ok: Bool, _ yes: String, _ no: String) -> some View {
        Label(ok ? yes : no, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? Color.green : Color.orange)
            .font(.callout)
    }

    @ViewBuilder private var headshotControls: some View {
        Section("Framing") {
            Picker("Crop", selection: $model.settings.crop) {
                ForEach(CropAspect.allCases) { Text($0.rawValue).tag($0) }
            }
        }
        Section("Background") {
            Picker("Style", selection: $model.settings.background) {
                ForEach(BackgroundStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            if model.settings.background == .blur {
                slider("Blur", $model.settings.backgroundBlur, 0.005...0.08)
            }
            if model.settings.background == .solid || model.settings.background == .gradient {
                ColorPicker("Colour", selection: backgroundColor, supportsOpacity: false)
            }
        }
        Section("Light & Colour") {
            Toggle("Auto enhance", isOn: $model.settings.autoEnhance)
            slider("Exposure", $model.settings.exposure, -1...1)
            slider("Contrast", $model.settings.contrast, 0.75...1.25)
            slider("Saturation", $model.settings.saturation, 0...2)
            slider("Warmth", $model.settings.warmth, -1...1)
        }
        Section("Retouch") {
            slider("Skin smoothing", $model.settings.smoothing, 0...1)
        }
        Section {
            Button("Reset Adjustments") { model.settings = HeadshotSettings() }
        }
    }

    @ViewBuilder private var avatarControls: some View {
        Section("Avatars") {
            Toggle("Export as circle", isOn: $model.circularAvatars)
            Text("Avatars are made from your headshot settings — change them on the Headshot tab.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout)
            Slider(value: value, in: range)
        }
    }

    private var backgroundColor: Binding<Color> {
        Binding {
            let c = model.settings.backgroundColor
            return Color(red: c.r, green: c.g, blue: c.b)
        } set: { color in
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            model.settings.backgroundColor = RGBColor(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
        }
    }
}

struct AvatarGallery: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)], spacing: 28) {
                ForEach(AvatarStyle.allCases) { style in
                    VStack(spacing: 10) {
                        Group {
                            if let image = model.avatars[style] {
                                Image(decorative: image, scale: 1).resizable().interpolation(.high)
                            } else {
                                Color.secondary.opacity(0.15)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(model.circularAvatars ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))
                        .shadow(radius: 4, y: 1)
                        Text(style.rawValue).font(.headline)
                        Button("Export…") { model.exportAvatar(style) }.controlSize(.small)
                    }
                }
            }
            .padding(28)
        }
    }
}
