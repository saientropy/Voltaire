import SwiftUI

struct AskSheetView: View {
    @Bindable var model: AskModel
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var focusedTarget: AskAccessibilityTarget?

    var body: some View {
        NavigationStack {
            Form {
                if let context = model.context {
                    Section("Current passage") {
                        Text(context.currentSentence)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(ReadingTokens.ink)
                            .textSelection(.enabled)
                    }
                }

                assistantContent
            }
            .scrollContentBackground(.hidden)
            .background(ReadingTokens.canvas)
            .tint(ReadingTokens.ink)
            .navigationTitle("Ask about this passage")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.dismiss()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.refreshAvailability()
                } else {
                    model.cancelRequest()
                }
            }
            .task(id: model.phase.accessibilityTarget) {
                let target = model.phase.accessibilityTarget
                guard let target else {
                    focusedTarget = nil
                    return
                }
                await Task.yield()
                guard model.phase.accessibilityTarget == target else { return }
                focusedTarget = target
            }
        }
        .accessibilityIdentifier("ask-sheet")
    }

    @ViewBuilder
    private var assistantContent: some View {
        switch model.phase {
        case .ready:
            Section {
                Button {
                    model.submit(.explain)
                } label: {
                    Label("Explain", systemImage: "text.magnifyingglass")
                }
                .accessibilityIdentifier("ask-explain-button")

                Button {
                    model.submit(.simplify)
                } label: {
                    Label("Simplify", systemImage: "text.badge.checkmark")
                }
                .accessibilityIdentifier("ask-simplify-button")

                TextField(
                    "Ask a short question",
                    text: $model.customQuestion,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .accessibilityIdentifier("ask-custom-field")

                Button {
                    model.submitCustomQuestion()
                } label: {
                    Label("Ask", systemImage: "arrow.up.circle.fill")
                }
                .disabled(!model.canSubmitCustomQuestion)
                .accessibilityIdentifier("ask-submit-button")
            } header: {
                Text("Choose one")
            } footer: {
                privacyFooter
            }

        case .responding:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Thinking on this iPad…")
                }

                Button("Cancel", role: .cancel) {
                    model.cancelRequest()
                }
                .accessibilityIdentifier("ask-cancel-button")
            } footer: {
                privacyFooter
            }

        case let .response(answer):
            Section {
                Text(answer)
                    .foregroundStyle(ReadingTokens.ink)
                    .textSelection(.enabled)
                    .accessibilityFocused($focusedTarget, equals: .response)
                    .accessibilityIdentifier("ask-response")

                Button("Ask another question") {
                    model.askAnother()
                }
            } header: {
                Text("Answer")
            } footer: {
                privacyFooter
            }

        case let .unavailable(availability):
            Section {
                Label(availability.userMessage, systemImage: "cpu")
                    .foregroundStyle(ReadingTokens.ink)
                    .accessibilityFocused($focusedTarget, equals: .unavailable)
                    .accessibilityIdentifier("ask-unavailable-message")

                Button("Try again") {
                    model.refreshAvailability()
                }
            } footer: {
                privacyFooter
            }

        case let .failed(error):
            Section {
                Label(error.userMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(ReadingTokens.ink)
                    .accessibilityFocused($focusedTarget, equals: .failure)
                    .accessibilityIdentifier("ask-failure-message")

                Button("Try again") {
                    model.askAnother()
                }
            } footer: {
                privacyFooter
            }
        }
    }

    private var privacyFooter: some View {
        Text("Answers are made on this iPad. No book text leaves the device.")
    }
}
