import SwiftUI

struct ReaderChromeView: View {
    let onBack: () -> Void
    let onContents: () -> Void
    let onAsk: () -> Void
    let onControls: () -> Void
    let showsContents: Bool
    let contentsEnabled: Bool
    let askEnabled: Bool

    var body: some View {
        HStack {
            ThemeIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back to library",
                accessibilityHint: "Stops narration if needed and returns to your library.",
                accessibilityIdentifier: "reader-back-button",
                action: onBack
            )
            .keyboardShortcut(.cancelAction)

            Spacer()

            HStack(spacing: 8) {
                if showsContents {
                    ThemeIconButton(
                        systemName: "list.bullet",
                        accessibilityLabel: "Contents",
                        accessibilityHint: contentsEnabled
                            ? "Shows the sections in this book."
                            : "Stop narration before moving to another section.",
                        accessibilityIdentifier: "reader-contents-button",
                        action: onContents
                    )
                    .disabled(!contentsEnabled)
                    .opacity(contentsEnabled ? 1 : 0.45)
                }

                ThemeIconButton(
                    systemName: "questionmark.bubble",
                    accessibilityLabel: "Ask about this passage",
                    accessibilityHint: askEnabled
                        ? "Explains or simplifies the current sentence on this iPad."
                        : "Stop narration before asking.",
                    accessibilityIdentifier: "ask-button",
                    action: onAsk
                )
                .disabled(!askEnabled)
                .opacity(askEnabled ? 1 : 0.45)

                ThemeIconButton(
                    systemName: "slider.horizontal.3",
                    accessibilityLabel: "Reading controls",
                    accessibilityHint: "Opens reading and narration controls.",
                    accessibilityIdentifier: "reading-controls-button",
                    action: onControls
                )
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

struct NarrationBarView: View {
    let state: NarrationState
    let voiceName: String?
    let onPauseOrResume: () -> Void
    let onStop: () -> Void

    private var isPaused: Bool {
        state == .paused
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                statusIcon
                statusText
                Spacer(minLength: 8)
                playbackControls
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    statusIcon
                    statusText
                }
                HStack {
                    Spacer()
                    playbackControls
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 520)
        .background(
            ReadingTokens.controlSurface,
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(ReadingTokens.hairline, lineWidth: 1)
        }
        .shadow(color: ReadingTokens.ink.opacity(0.12), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("narration-bar")
    }

    private var statusIcon: some View {
        Image(systemName: isPaused ? "pause.fill" : "waveform")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 34, height: 34)
            .foregroundStyle(ReadingTokens.canvas)
            .background(ReadingTokens.ink, in: Circle())
            .accessibilityHidden(true)
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isPaused ? "Narration paused" : "Reading with \(voiceName ?? "your narrator")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ReadingTokens.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(isPaused ? "Your place is preserved" : "Phrase highlighting is live")
                .font(.caption)
                .foregroundStyle(ReadingTokens.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            ThemeIconButton(
                systemName: isPaused ? "play.fill" : "pause.fill",
                accessibilityLabel: isPaused ? "Resume narration" : "Pause narration",
                accessibilityHint: isPaused ? "Continues from the paused phrase." : "Pauses on the current phrase.",
                accessibilityIdentifier: "narration-pause-or-resume",
                compact: true,
                action: onPauseOrResume
            )

            ThemeIconButton(
                systemName: "stop.fill",
                accessibilityLabel: "Stop narration",
                accessibilityHint: "Stops speech and keeps your reading place.",
                accessibilityIdentifier: "narration-stop",
                compact: true,
                action: onStop
            )
        }
    }
}

private struct ThemeIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let accessibilityIdentifier: String
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: compact ? 15 : 17, weight: .semibold))
                .frame(
                    width: ReadingTokens.touchTarget,
                    height: ReadingTokens.touchTarget
                )
                .foregroundStyle(ReadingTokens.ink)
                .background(ReadingTokens.controlSurface, in: Circle())
                .overlay {
                    Circle()
                        .stroke(ReadingTokens.hairline, lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
