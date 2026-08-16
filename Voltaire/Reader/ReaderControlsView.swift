import SwiftUI

/// Reader controls presented as a system-owned sheet so that hit testing
/// is managed by SwiftUI rather than competing ZStack overlays.
///
/// Controls bind **live** to `model.linePreset`: the mode Button and
/// Stepper mutate `linePreset` directly, so changes take effect
/// immediately with no separate draft or Apply transaction. **Done**
/// dismisses the sheet. The current sentence stays anchored because
/// `SentenceLayoutEngine.makeWindow` always anchors on `position`.
struct ReaderControlsView: View {
    @Bindable var model: ReaderModel
    @Environment(\.scenePhase) private var scenePhase

    private var isFullPage: Bool {
        model.linePreset == .fullPage
    }

    /// Live binding for the Stepper that reads/writes the line count on
    /// `model.linePreset`. The Stepper is only shown in line mode, so
    /// the getter fallback is never visible.
    private var lineCount: Binding<Int> {
        Binding(
            get: { model.linePreset.lineCount ?? 5 },
            set: { newCount in model.linePreset = .lines(newCount) }
        )
    }

    private var textSize: Binding<ReaderAppearance.TextSize> {
        Binding(
            get: { model.appearance.textSize },
            set: { value in
                var appearance = model.appearance
                appearance.textSize = value
                model.appearance = appearance
            }
        )
    }

    private var lineSpacing: Binding<ReaderAppearance.LineSpacing> {
        Binding(
            get: { model.appearance.lineSpacing },
            set: { value in
                var appearance = model.appearance
                appearance.lineSpacing = value
                model.appearance = appearance
            }
        )
    }

    private var margin: Binding<ReaderAppearance.Margin> {
        Binding(
            get: { model.appearance.margin },
            set: { value in
                var appearance = model.appearance
                appearance.margin = value
                model.appearance = appearance
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !model.narration.availableVoices.isEmpty {
                        Picker("Voice", selection: voiceSelection) {
                            ForEach(model.narration.availableVoices, id: \.identifier) { voice in
                                Text(voice.menuLabel)
                                    .tag(voice.identifier)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(!model.narration.canChangeVoice)
                        .accessibilityLabel("Narration voice")
                        .accessibilityHint("Chooses an installed Premium or Enhanced English voice.")
                        .accessibilityIdentifier("narration-voice-picker")

                        Picker("Pace", selection: paceSelection) {
                            ForEach(NarrationPace.allCases) { pace in
                                Text(pace.label).tag(pace)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!model.narration.canChangePace)
                        .accessibilityLabel("Narration pace")
                        .accessibilityHint("Sets the speed for voice previews and future narration. Your reading place stays the same.")
                        .accessibilityIdentifier("narration-pace-picker")

                        Button {
                            model.narration.previewSelectedVoice()
                        } label: {
                            Label("Preview voice", systemImage: "speaker.wave.2")
                        }
                        .disabled(!model.narration.canPreviewVoice)
                        .accessibilityHint("Plays a short sample without moving your reading position.")
                        .accessibilityIdentifier("narration-voice-preview")
                    }

                    narrationControls
                } header: {
                    Text("Narration")
                } footer: {
                    Text(narrationStatus)
                }

                Section {
                    Picker("Text size", selection: textSize) {
                        ForEach(ReaderAppearance.TextSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityHint("Changes the book text size and keeps your place.")
                    .accessibilityIdentifier("reader-text-size-picker")

                    Picker("Line spacing", selection: lineSpacing) {
                        ForEach(ReaderAppearance.LineSpacing.allCases) { spacing in
                            Text(spacing.label).tag(spacing)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityHint("Changes the space between book lines and keeps your place.")
                    .accessibilityIdentifier("reader-line-spacing-picker")

                    Picker("Margins", selection: margin) {
                        ForEach(ReaderAppearance.Margin.allCases) { margin in
                            Text(margin.label).tag(margin)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityHint("Changes the width of the book margins and keeps your place.")
                    .accessibilityIdentifier("reader-margin-picker")

                    Button("Use book defaults") {
                        model.appearance = .bookDefault
                    }
                    .disabled(model.appearance == .bookDefault)
                    .accessibilityHint("Restores the standard text size, line spacing, and margins.")
                    .accessibilityIdentifier("reader-appearance-reset")
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Changes apply immediately and stay the same for every book.")
                }

                Section {
                    Button {
                        if model.linePreset == .fullPage {
                            model.linePreset = .lines(model.linePreset.lineCount ?? 5)
                        } else {
                            model.linePreset = .fullPage
                        }
                    } label: {
                        HStack {
                            Text(isFullPage ? "Use line window" : "Use full page")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .accessibilityLabel(isFullPage ? "Use line window" : "Use full page")
                    .accessibilityHint("Switches between full page scrolling and an exact visible-line window.")

                    if !isFullPage {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Visible lines: \(lineCount.wrappedValue)")
                                .font(.body)
                            Stepper(
                                "Visible lines: \(lineCount.wrappedValue)",
                                value: lineCount,
                                in: 3...20
                            )
                            .labelsHidden()
                            .accessibilityLabel("Visible lines")
                            .accessibilityValue("\(lineCount.wrappedValue) lines")
                            .accessibilityHint("Choose the exact number of visible lines, from 3 through 20. The current sentence stays anchored.")
                        }
                    }
                } header: {
                    Text("Reading window")
                } footer: {
                    Text("The current sentence stays anchored when you change the visible window.")
                }

            }
            .scrollContentBackground(.hidden)
            .background(ReadingTokens.canvas)
            .tint(ReadingTokens.ink)
            .navigationTitle("Reading")
            .onAppear {
                model.narration.refreshVoices()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.narration.refreshVoices()
                } else {
                    model.narration.stopVoicePreview()
                }
            }
            .onDisappear {
                model.narration.stopVoicePreview()
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.cancel()
                    }
                    .accessibilityLabel("Done")
                    .accessibilityHint("Returns to the book.")
                }
            }
        }
    }

    private var voiceSelection: Binding<String> {
        Binding(
            get: {
                model.narration.selectedVoiceIdentifier
                    ?? model.narration.availableVoices.first?.identifier
                    ?? ""
            },
            set: { model.narration.selectVoice(identifier: $0) }
        )
    }

    private var paceSelection: Binding<NarrationPace> {
        Binding(
            get: { model.narration.selectedPace },
            set: { model.narration.selectPace($0) }
        )
    }

    @ViewBuilder
    private var narrationControls: some View {
        switch model.narration.state {
        case .idle, .stopped, .finished:
            if model.narration.availableVoices.isEmpty {
                Label(
                    "Download a Premium or Enhanced English voice to use narration.",
                    systemImage: "speaker.slash"
                )
                .foregroundStyle(ReadingTokens.secondaryInk)
                .accessibilityIdentifier("narration-voice-setup")
            } else {
                Button {
                    model.startNarration()
                } label: {
                    Label("Start narration", systemImage: "play.fill")
                }
                .accessibilityHint("Reads \(model.document.title) aloud from the current sentence.")
            }

        case .speaking:
            Button {
                model.narration.pause()
            } label: {
                Label("Pause narration", systemImage: "pause.fill")
            }
            .accessibilityHint("Pauses speech and keeps the current phrase highlighted.")

            Button(role: .destructive) {
                model.narration.stop()
            } label: {
                Label("Stop narration", systemImage: "stop.fill")
            }
            .accessibilityHint("Stops speech and keeps your reading position.")

        case .paused:
            Button {
                model.narration.resume()
            } label: {
                Label("Resume narration", systemImage: "play.fill")
            }
            .accessibilityHint("Resumes speech from the paused phrase.")

            Button(role: .destructive) {
                model.narration.stop()
            } label: {
                Label("Stop narration", systemImage: "stop.fill")
            }
            .accessibilityHint("Stops speech and keeps your reading position.")
        }
    }

    private var narrationStatus: String {
        if model.narration.availableVoices.isEmpty {
            return NarrationModel.voiceSetupMessage
        }
        if let message = model.narration.message {
            return message
        }

        let voiceDescription = model.narration.selectedVoice.map {
            "\($0.displayName), \($0.qualityLabel). "
        } ?? ""
        let paceDescription = "\(model.narration.selectedPace.label) pace. "

        return switch model.narration.state {
        case .idle:
            "\(voiceDescription)\(paceDescription)Narration starts at the current sentence."
        case .speaking:
            "\(voiceDescription)\(paceDescription)Speaking from your current place."
        case .paused:
            "\(voiceDescription)\(paceDescription)Paused at the current phrase."
        case .stopped:
            "\(voiceDescription)\(paceDescription)Stopped. Your current sentence is preserved."
        case .finished:
            "\(voiceDescription)\(paceDescription)Finished. Start again from the final sentence."
        }
    }
}
