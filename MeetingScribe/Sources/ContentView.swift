import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    @StateObject private var history = HistoryStore()
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player = PlaybackController()
    @State private var isTargeted = false
    @State private var showCopiedBadge = false
    @State private var activeTab: ResultTab = .transcript
    @State private var isSidebarVisible = true
    @State private var selectedSessionID: UUID?
    @State private var showSettings = false
    @State private var hasAPIKey = KeychainStore.load() != nil

    private enum ResultTab: String, CaseIterable {
        case transcript = "Transcript"
        case summary = "Summary"
    }

    private let backgroundTop = Color(red: 0.995, green: 0.97, blue: 0.93)
    private let backgroundBottom = Color(red: 0.97, green: 0.93, blue: 0.88)

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView(
                    history: history,
                    selectedSessionID: $selectedSessionID,
                    onSelect: { session in
                        player.pause()
                        selectedSessionID = session.id
                        viewModel.loadFromHistory(session)
                        activeTab = .transcript
                    },
                    onDelete: { session in
                        if selectedSessionID == session.id {
                            selectedSessionID = nil
                            player.pause()
                            viewModel.reset()
                        }
                        history.delete(session)
                    }
                )
                .frame(width: 220)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                header

                Group {
                    if viewModel.isProcessing {
                        processingView
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else if viewModel.hasResult {
                        transcriptView
                            .transition(.opacity)
                    } else {
                        dropZone
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .animation(.easeOut(duration: 0.3), value: viewModel.isProcessing)
                .animation(.easeOut(duration: 0.3), value: viewModel.hasResult)
            }
            .background(
                LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
            )
        }
        .animation(.easeOut(duration: 0.25), value: isSidebarVisible)
        .onAppear {
            viewModel.history = history
            if !hasAPIKey {
                showSettings = true
            }
        }
        .onChange(of: viewModel.playableAudioURL) { url in
            if let url {
                player.load(url: url)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(hasAPIKey: $hasAPIKey)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                isSidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .frame(width: 32, height: 32)
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Scribe")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            if viewModel.hasResult && !viewModel.isProcessing {
                Button {
                    player.pause()
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.reset()
                        selectedSessionID = nil
                        activeTab = .transcript
                    }
                } label: {
                    Label("New Transcript", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PillButtonStyle(tint: .secondary, size: .compact))
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }

    // MARK: Drop zone / landing

    private var dropZone: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 120, height: 120)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor.gradient)
                        .symbolRenderingMode(.hierarchical)
                }
                .scaleEffect(isTargeted ? 1.08 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isTargeted)

                VStack(spacing: 6) {
                    Text("Drop a recording to transcribe")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))

                    Text("AirDrop a voice memo here, or pick a file below")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 64)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.22))
                    )
            )
            .padding(.horizontal, 40)
            .onDrop(of: [UTType.audio, UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }

            VStack(spacing: 10) {
                languagePicker
                summaryStylePicker
            }

            HStack(spacing: 14) {
                Button {
                    chooseFile()
                } label: {
                    Label("Choose File", systemImage: "folder.fill")
                }
                .buttonStyle(PillButtonStyle(tint: .secondary, size: .large))

                if recorder.isRecording {
                    Button {
                        if let url = recorder.stop() {
                            viewModel.process(fileURL: url)
                        }
                    } label: {
                        Label(timeString(recorder.elapsed), systemImage: "stop.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: .red, size: .large, prominent: true))
                } else {
                    Button {
                        recorder.requestAccessAndStart()
                    } label: {
                        Label("Record Instead", systemImage: "mic.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: .accentColor, size: .large, prominent: true))
                }
            }

            if recorder.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .opacity(0.9)
                    Text("Recording…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 44)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
    }

    private var languagePicker: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Spoken language")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 12)
            Picker("", selection: $viewModel.selectedLanguage) {
                ForEach(SupportedLanguages.all) { lang in
                    Text(lang.name).tag(lang.id)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.6))
        )
    }

    private var summaryStylePicker: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Summary style")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 12)
            Picker("", selection: $viewModel.summaryStyle) {
                ForEach(SummaryStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.6))
        )
    }

    // MARK: Processing

    private var processingView: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill((viewModel.isWaitingToResume ? Color.orange : Color.accentColor).opacity(0.1))
                    .frame(width: 88, height: 88)
                if viewModel.isWaitingToResume {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.orange.gradient)
                } else {
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(Color.accentColor)
                }
            }

            VStack(spacing: 8) {
                Text(viewModel.isWaitingToResume ? "Paused — rate limited" : viewModel.progressText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                if viewModel.isWaitingToResume, let resumeAt = viewModel.resumeAt {
                    Text("Groq blocked requests after 8 retries. Scribe will resume automatically at \(resumeAt.formatted(date: .omitted, time: .shortened)).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    Text(viewModel.sourceName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.isWaitingToResume {
                ProgressView(value: viewModel.totalChunks == 0 ? nil : Double(viewModel.completedChunks), total: Double(max(viewModel.totalChunks, 1)))
                    .frame(width: 280)
                    .tint(Color.accentColor)
            } else {
                Text("\(viewModel.completedChunks) of \(viewModel.totalChunks) parts already transcribed")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: Transcript + editing

    private var transcriptView: some View {
        VStack(spacing: 0) {
            tabSwitcher

            if let lang = viewModel.detectedLanguageLabel {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("Detected language: \(lang)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 26)
                .padding(.top, 10)
            }

            Group {
                if activeTab == .transcript {
                    transcriptList
                } else {
                    summaryPane
                }
            }

            if activeTab == .transcript {
                playerBar
                Divider().opacity(0.3)
            }

            HStack(spacing: 10) {
                Text(viewModel.sourceName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if showCopiedBadge {
                    Text("Copied")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Button {
                    copyActiveContent()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(PillButtonStyle(tint: .secondary, size: .compact))

                Button {
                    saveActiveContent()
                } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PillButtonStyle(tint: .accentColor, size: .compact, prominent: true))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(ResultTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { activeTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(activeTab == tab ? .white : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(activeTab == tab ? Color.accentColor.gradient : Color.clear.gradient)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.55))
        )
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private var transcriptList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.segments) { segment in
                    SegmentRow(
                        segment: segment,
                        isPlaying: player.playingSegmentID == segment.id && player.isPlaying,
                        onPlay: { player.playSegment(segment) },
                        onCommit: { newText in viewModel.updateSegment(segment.id, text: newText) },
                        onDelete: { viewModel.deleteSegment(segment.id) }
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    private var summaryPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Style")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { viewModel.summaryStyle },
                    set: { viewModel.setSummaryStyle($0) }
                )) {
                    ForEach(SummaryStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

                if viewModel.isSummarizing {
                    ProgressView()
                        .controlSize(.small)
                } else if !viewModel.summary.isEmpty {
                    Button {
                        viewModel.summarize()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PillButtonStyle(tint: .secondary, size: .compact))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.isSummarizing && viewModel.summary.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Summarizing…")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else if let error = viewModel.summaryError {
                        VStack(spacing: 10) {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                            Button {
                                viewModel.summarize()
                            } label: {
                                Label("Try Again", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(PillButtonStyle(tint: .accentColor, size: .compact, prominent: true))
                        }
                        .padding(.top, 50)
                        .padding(.horizontal, 30)
                    } else if !viewModel.summary.isEmpty {
                        Text(viewModel.summary)
                            .font(.system(size: 14))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.white.opacity(0.65))
                            )
                            .padding(.horizontal, 22)
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private var playerBar: some View {
        HStack(spacing: 16) {
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor.gradient)
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .tint(Color.accentColor)

            Text(TranscriptSegment.formatTime(player.currentTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            speedControl
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.white.opacity(0.5))
    }

    private var speedControl: some View {
        Menu {
            ForEach(PlaybackController.availableRates, id: \.self) { rate in
                Button {
                    player.playbackRate = rate
                } label: {
                    if rate == player.playbackRate {
                        Label(speedLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(rate))
                    }
                }
            }
        } label: {
            Text(speedLabel(player.playbackRate))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.accentColor.opacity(0.12))
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func speedLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))x" : String(format: "%.2gx", rate)
    }

    // MARK: Actions

    private var activeContent: String {
        activeTab == .transcript ? viewModel.transcript : viewModel.summary
    }

    private func copyActiveContent() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(activeContent, forType: .string)
        withAnimation { showCopiedBadge = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { showCopiedBadge = false }
        }
    }

    private func saveActiveContent() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let suffix = activeTab == .transcript ? "" : "_summary"
        panel.nameFieldStringValue = (viewModel.sourceName as NSString).deletingPathExtension + suffix + ".txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? activeContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.process(fileURL: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                DispatchQueue.main.async {
                    viewModel.process(fileURL: url)
                }
            }
        }
        return true
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Segment row

private struct SegmentRow: View {
    let segment: TranscriptSegment
    let isPlaying: Bool
    let onPlay: () -> Void
    let onCommit: (String) -> Void
    let onDelete: () -> Void

    @State private var text: String
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    init(segment: TranscriptSegment, isPlaying: Bool, onPlay: @escaping () -> Void, onCommit: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.segment = segment
        self.isPlaying = isPlaying
        self.onPlay = onPlay
        self.onCommit = onCommit
        self.onDelete = onDelete
        _text = State(initialValue: segment.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "waveform" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPlaying ? .white : Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isPlaying ? Color.accentColor : Color.accentColor.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(segment.timeLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor.opacity(0.7))

                TextEditor(text: $text)
                    .font(.system(size: 14.5))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 24)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: isFocused) { focused in
                        if !focused { onCommit(text) }
                    }
            }

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isPlaying ? 0.95 : 0.65))
                .shadow(color: .black.opacity(isPlaying ? 0.08 : 0.03), radius: isPlaying ? 10 : 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isPlaying ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.2), value: isPlaying)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Button style

private struct PillButtonStyle: ButtonStyle {
    enum Size {
        case compact, large

        var horizontalPadding: CGFloat { self == .compact ? 16 : 22 }
        var verticalPadding: CGFloat { self == .compact ? 10 : 15 }
        var fontSize: CGFloat { self == .compact ? 12.5 : 14.5 }
    }

    var tint: Color
    var size: Size = .large
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.fontSize, weight: .semibold))
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .foregroundStyle(prominent ? .white : tint)
            .background(
                Group {
                    if prominent {
                        Capsule().fill(tint.gradient)
                    } else {
                        Capsule().fill(.white.opacity(configuration.isPressed ? 0.5 : 0.8))
                    }
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(prominent ? 0 : 0.25), lineWidth: 1.2)
            )
            .shadow(color: prominent ? tint.opacity(0.35) : .black.opacity(0.04), radius: configuration.isPressed ? 2 : 8, x: 0, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
