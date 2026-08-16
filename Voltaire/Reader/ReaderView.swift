import SwiftUI

private enum ReaderSheet: String, Identifiable {
    case contents
    case controls
    case ask

    var id: String { rawValue }
}

private struct PendingFiniteAnchor: Equatable {
    let sentenceID: String
    let sourceLocation: Int
}

struct ReaderView: View {
    let document: ReaderDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ReaderModel
    @State private var askModel: AskModel
    @State private var presentedSheet: ReaderSheet?
    @State private var askDetent: PresentationDetent = .medium
    @State private var pendingFiniteAnchor: PendingFiniteAnchor?
    @State private var pendingFinitePosition: ReaderPosition?
    @ScaledMetric(relativeTo: .body) private var dynamicTypeScale: CGFloat = 1

    init(
        document: ReaderDocument,
        initialPosition: ReaderPosition? = nil,
        initialLinePreset: SentenceLayoutEngine.LinePreset = .fullPage,
        initialAppearance: ReaderAppearance = .bookDefault,
        onPositionChange: @escaping (ReaderPosition) -> Void = { _ in },
        onLinePresetChange: @escaping (SentenceLayoutEngine.LinePreset) -> Void = { _ in },
        onAppearanceChange: @escaping (ReaderAppearance) -> Void = { _ in },
        assistantService: any AssistantService = OnDeviceAssistantService()
    ) {
        self.document = document
        let readerModel = ReaderModel(
            document: document,
            speechEngine: AVSpeechEngine(),
            initialPosition: initialPosition,
            initialLinePreset: initialLinePreset,
            initialAppearance: initialAppearance,
            onPositionChange: onPositionChange,
            onLinePresetChange: onLinePresetChange,
            onAppearanceChange: onAppearanceChange
        )
        let showsControls = ProcessInfo.processInfo.arguments.contains("--show-reading-controls")
        if showsControls {
            readerModel.controlsVisible = true
        }
        _model = State(initialValue: readerModel)
        _askModel = State(initialValue: AskModel(service: assistantService))
        _presentedSheet = State(initialValue: showsControls ? .controls : nil)
    }

    var body: some View {
        GeometryReader { proxy in
            let readingColumnWidth = min(proxy.size.width, 900)
            let preferredPagePadding = CGFloat(model.appearance.margin.points)
            let maximumPagePadding = max((readingColumnWidth - 280) / 2, 16)
            let pagePadding = min(preferredPagePadding, maximumPagePadding)
            let contentWidth = max(readingColumnWidth - pagePadding * 2, 1)
            let fontSize = CGFloat(model.appearance.textSize.points) * dynamicTypeScale
            let lineSpacing = CGFloat(
                model.appearance.lineSpacing.points(for: Double(fontSize))
            )
            let layoutIdentity = [
                String(Int((contentWidth * 8).rounded())),
                String(Int((fontSize * 8).rounded())),
                model.appearance.lineSpacing.rawValue
            ].joined(separator: "-")
            ZStack(alignment: .bottom) {
                let readingWindow = model.window(width: contentWidth, fontSize: fontSize)
                ReadingCanvas(
                    document: document,
                    chapterTitle: model.currentChapterTitle,
                    window: readingWindow,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    pagePadding: pagePadding,
                    activeSentenceID: model.narration.activeSentenceID,
                    activeRange: model.narration.activeRange,
                    scrollable: model.linePreset == .fullPage,
                    navigationEnabled: model.navigationEnabled,
                    canonicalLineID: readingWindow.anchorLineID,
                    onVisibleLineChange: { lineID in
                        if model.linePreset == .fullPage {
                            model.updatePosition(
                                for: lineID,
                                in: readingWindow
                            )
                        } else {
                            guard let line = readingWindow.lines.first(where: {
                                $0.id == lineID
                            }) else {
                                return
                            }
                            pendingFiniteAnchor = PendingFiniteAnchor(
                                sentenceID: line.sentenceID,
                                sourceLocation: line.sourceRange.location
                            )
                            pendingFinitePosition = model.position(
                                for: lineID,
                                width: contentWidth,
                                fontSize: fontSize
                            )
                        }
                    }
                )
                .id(layoutIdentity)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        let width = max(proxy.size.width, 1)
                        let horizontalPosition = value.location.x / width
                        if model.linePreset.lineCount != nil,
                           model.navigationEnabled,
                           horizontalPosition < 0.25 {
                            discardPendingFinitePosition()
                            model.goBack(width: contentWidth, fontSize: fontSize)
                        } else if model.linePreset.lineCount != nil,
                                  model.navigationEnabled,
                                  horizontalPosition > 0.75 {
                            discardPendingFinitePosition()
                            model.advance(width: contentWidth, fontSize: fontSize)
                        } else {
                            presentControls()
                        }
                    }
                )
                .modifier(ReaderWindowAccessibilityActions(
                    enabled: model.linePreset.lineCount != nil && model.navigationEnabled,
                    goBack: {
                        guard model.navigationEnabled else { return }
                        discardPendingFinitePosition()
                        model.goBack(width: contentWidth, fontSize: fontSize)
                    },
                    advance: {
                        guard model.navigationEnabled else { return }
                        discardPendingFinitePosition()
                        model.advance(width: contentWidth, fontSize: fontSize)
                    }
                ))
                .onChange(of: model.narration.activeRange) { _, _ in
                    model.revealActivePhrase(width: contentWidth, fontSize: fontSize)
                }
                .onChange(of: model.narration.activeSentenceID) { _, _ in
                    model.revealActivePhrase(width: contentWidth, fontSize: fontSize)
                }
                .onChange(of: layoutIdentity) { _, _ in
                    reconcilePendingFinitePosition(
                        width: contentWidth,
                        fontSize: fontSize
                    )
                    commitPendingFinitePosition()
                    model.revealActivePhrase(width: contentWidth, fontSize: fontSize)
                }

                if presentedSheet == nil,
                   model.linePreset.lineCount != nil,
                   model.navigationEnabled {
                    ReaderKeyboardShortcuts(
                        goBack: {
                            discardPendingFinitePosition()
                            model.goBack(width: contentWidth, fontSize: fontSize)
                        },
                        advance: {
                            discardPendingFinitePosition()
                            model.advance(width: contentWidth, fontSize: fontSize)
                        }
                    )
                }

            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    ReaderChromeView(
                        onBack: {
                            commitPendingFinitePosition()
                            guard model.stopForExit() else { return }
                            dismiss()
                        },
                        onContents: presentContents,
                        onAsk: {
                            guard presentedSheet == nil,
                                  model.navigationEnabled else {
                                return
                            }
                            commitPendingFinitePosition()
                            guard let context = AskContext(
                                      document: document,
                                      position: model.position
                                  ) else {
                                return
                            }
                            askDetent = .medium
                            askModel.present(context: context)
                            presentedSheet = .ask
                        },
                        onControls: presentControls,
                        showsContents: model.chapters.count > 1,
                        contentsEnabled: model.navigationEnabled,
                        askEnabled: model.navigationEnabled
                    )
                    .frame(width: contentWidth)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(ReadingTokens.canvas)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.showsNarrationBar {
                    NarrationBarView(
                        state: model.narration.state,
                        voiceName: model.narration.selectedVoice?.displayName,
                        onPauseOrResume: {
                            if model.narration.state == .paused {
                                model.narration.resume()
                            } else {
                                model.narration.pause()
                            }
                        },
                        onStop: model.narration.stop
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                }
            }
            .background {
                ReadingTokens.canvas
                    .ignoresSafeArea()
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.controlsVisible)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.showsNarrationBar)
        }
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
#endif
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .contents:
                ReaderContentsView(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .controls:
                ReaderControlsView(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .onDisappear {
                        model.cancel()
                    }
            case .ask:
                AskSheetView(model: askModel)
                    .presentationDetents([.medium, .large], selection: $askDetent)
                    .presentationDragIndicator(.visible)
                    .onDisappear {
                        askModel.dismiss()
                    }
            }
        }
        .onChange(of: model.controlsVisible) { _, visible in
            if visible, presentedSheet == nil {
                presentedSheet = .controls
            } else if !visible, presentedSheet == .controls {
                presentedSheet = nil
            }
        }
        .onChange(of: askModel.isPresented) { _, visible in
            if visible, presentedSheet == nil {
                presentedSheet = .ask
            } else if !visible, presentedSheet == .ask {
                presentedSheet = nil
            }
        }
        .onChange(of: askModel.phase) { _, phase in
            if case .response = phase {
                askDetent = .large
            } else if phase == .ready {
                askDetent = .medium
            }
        }
        .onChange(of: model.position.sentenceID) { _, sentenceID in
            askModel.dismissIfContextChanged(currentSentenceID: sentenceID)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                commitPendingFinitePosition()
            }
        }
        .onDisappear {
            commitPendingFinitePosition()
            askModel.dismiss()
            _ = model.stopForExit()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(document.title), \(model.currentChapterTitle)")
        .accessibilityIdentifier("reader-screen")
    }

    private func presentControls() {
        guard presentedSheet == nil else { return }
        commitPendingFinitePosition()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            model.showControls()
        }
        presentedSheet = .controls
    }

    private func presentContents() {
        guard presentedSheet == nil,
              model.navigationEnabled,
              model.chapters.count > 1 else {
            return
        }
        commitPendingFinitePosition()
        presentedSheet = .contents
    }

    private func commitPendingFinitePosition() {
        guard let pendingFinitePosition else { return }
        discardPendingFinitePosition()
        guard model.position != pendingFinitePosition else { return }
        model.position = pendingFinitePosition
    }

    private func reconcilePendingFinitePosition(width: Double, fontSize: Double) {
        guard let pendingFiniteAnchor else { return }
        pendingFinitePosition = model.position(
            forSentenceID: pendingFiniteAnchor.sentenceID,
            sourceLocation: pendingFiniteAnchor.sourceLocation,
            width: width,
            fontSize: fontSize
        )
    }

    private func discardPendingFinitePosition() {
        pendingFiniteAnchor = nil
        pendingFinitePosition = nil
    }

}

private struct ReaderKeyboardShortcuts: View {
    let goBack: () -> Void
    let advance: () -> Void

    var body: some View {
        ZStack {
            Button("Previous reading window", action: goBack)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Next reading window", action: advance)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(width: 44, height: 44)
        .opacity(0.001)
        .offset(x: -4_000, y: -4_000)
        .accessibilityHidden(true)
    }
}

private struct ReaderWindowAccessibilityActions: ViewModifier {
    let enabled: Bool
    let goBack: () -> Void
    let advance: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        advance()
                    case .decrement:
                        goBack()
                    @unknown default:
                        break
                    }
                }
                .accessibilityHint(
                    "Swipe up for the next reading window or down for the previous one."
                )
        } else {
            content
        }
    }
}

private struct ReadingCanvas: View {
    let document: ReaderDocument
    let chapterTitle: String
    let window: ReaderWindow
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let pagePadding: CGFloat
    let activeSentenceID: String?
    let activeRange: NSRange?
    let scrollable: Bool
    let navigationEnabled: Bool
    let canonicalLineID: String?
    let onVisibleLineChange: (String) -> Void
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var settleGeneration = 0
    @State private var scrollCoordinator = ReaderScrollCoordinator()
    @State private var finiteScrollPosition = ScrollPosition(idType: String.self)
    @State private var finiteScrollPhase: ScrollPhase = .idle
    @State private var finiteSettleGeneration = 0
    @State private var finiteScrollCoordinator = ReaderScrollCoordinator()

    var body: some View {
        Group {
            if scrollable {
                ScrollViewReader { proxy in
                    ScrollView {
                        fullPageContent
                    }
                    .scrollPosition($scrollPosition)
                    .scrollDisabled(!navigationEnabled)
                    .onAppear {
                        scheduleInitialScroll(using: proxy)
                    }
                    .onChange(of: canonicalLineID) { _, lineID in
                        guard activeLineID == nil,
                              let lineID,
                              scrollCoordinator.prepareProgrammaticScroll(to: lineID) else {
                            return
                        }
                        proxy.scrollTo(lineID, anchor: .top)
                    }
                    .onChange(of: activeLineID) { _, lineID in
                        guard let lineID else { return }
                        scrollCoordinator.prepareProgrammaticScroll(to: lineID)
                        proxy.scrollTo(lineID, anchor: .center)
                    }
                    .onScrollTargetVisibilityChange(
                        idType: String.self,
                        threshold: 0.5
                    ) { visibleLineIDs in
                        let visibleSet = Set(visibleLineIDs)
                        let orderedFallback = window.lines.first {
                            visibleSet.contains($0.id)
                        }?.id
                        scrollCoordinator.observeVisibleLine(
                            scrollPosition.viewID(type: String.self) ?? orderedFallback
                        )
                    }
                    .onScrollPhaseChange { _, newPhase in
                        scrollPhase = newPhase
                        settleGeneration &+= 1
                        let generation = settleGeneration

                        switch newPhase {
                        case .tracking, .interacting, .decelerating:
                            scrollCoordinator.userInteractionBegan()
                        case .idle:
                            Task { @MainActor in
                                await Task.yield()
                                guard scrollPhase == .idle,
                                      settleGeneration == generation else {
                                    return
                                }
                                guard let userPosition = scrollCoordinator.finishUserScroll(
                                    finalVisibleLineID: scrollPosition.viewID(type: String.self),
                                    navigationEnabled: navigationEnabled
                                ) else { return }
                                onVisibleLineChange(userPosition)
                            }
                        case .animating:
                            break
                        }
                    }
                }
            } else {
                ViewThatFits(in: .vertical) {
                    finiteContent
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        finiteContent
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .scrollPosition($finiteScrollPosition)
                    .id("\(window.anchorLineID)-\(window.requestedLineCount ?? 0)")
                    .scrollDisabled(!navigationEnabled)
                    .onAppear {
                        finiteScrollCoordinator.prepareProgrammaticScroll(
                            to: window.anchorLineID
                        )
                    }
                    .onScrollTargetVisibilityChange(
                        idType: String.self,
                        threshold: 0.5
                    ) { visibleLineIDs in
                        let visibleSet = Set(visibleLineIDs)
                        let orderedFallback = window.lines.first {
                            visibleSet.contains($0.id)
                        }?.id
                        finiteScrollCoordinator.observeVisibleLine(
                            finiteScrollPosition.viewID(type: String.self) ?? orderedFallback
                        )
                    }
                    .onScrollPhaseChange { _, newPhase in
                        finiteScrollPhase = newPhase
                        finiteSettleGeneration &+= 1
                        let generation = finiteSettleGeneration

                        switch newPhase {
                        case .tracking, .interacting, .decelerating:
                            finiteScrollCoordinator.userInteractionBegan()
                        case .idle:
                            Task { @MainActor in
                                await Task.yield()
                                guard finiteScrollPhase == .idle,
                                      finiteSettleGeneration == generation else {
                                    return
                                }
                                guard let userPosition = finiteScrollCoordinator.finishUserScroll(
                                    finalVisibleLineID: finiteScrollPosition.viewID(type: String.self),
                                    navigationEnabled: navigationEnabled
                                ) else { return }
                                onVisibleLineChange(userPosition)
                            }
                        case .animating:
                            break
                        }
                    }
                    .accessibilityLabel("Reading window. Scroll to read every selected line.")
                    .accessibilityIdentifier("reader-window-overflow-scroll")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(ReadingTokens.canvas)
    }

    private var fullPageContent: some View {
        LazyVStack(alignment: .leading, spacing: lineSpacing) {
            readingRows
        }
        .scrollTargetLayout()
        .padding(.horizontal, pagePadding)
        .padding(.top, 96)
        .padding(.bottom, 48)
        .frame(maxWidth: 900, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var finiteContent: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            readingRows
        }
        .scrollTargetLayout()
        .padding(.horizontal, pagePadding)
        .padding(.top, 96)
        .padding(.bottom, 48)
        .frame(maxWidth: 900, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var readingRows: some View {
        Text(chapterTitle.uppercased())
            .font(.system(.caption, design: .serif, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(ReadingTokens.secondaryInk)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)

        ForEach(window.lines) { line in
            highlightedLine(line)
                .font(.system(size: fontSize, design: .serif))
                .foregroundStyle(ReadingTokens.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(line.id)
                .accessibilityLabel(accessibilitySentenceLabel(for: line))
                .accessibilityHidden(!isFirstVisibleLineOfSentence(line))
        }

    }

    private func isFirstVisibleLineOfSentence(_ line: ReaderLine) -> Bool {
        window.lines.first(where: { $0.sentenceID == line.sentenceID })?.id == line.id
    }

    private func accessibilitySentenceLabel(for line: ReaderLine) -> String {
        window.lines
            .filter { $0.sentenceID == line.sentenceID }
            .map(\.text)
            .joined(separator: " ")
    }

    private var activeLineID: String? {
        guard let activeSentenceID, let activeRange else { return nil }
        return window.lines.first {
            $0.sentenceID == activeSentenceID &&
            NSIntersectionRange($0.sourceRange, activeRange).length > 0
        }?.id
    }

    private func scheduleInitialScroll(using proxy: ScrollViewProxy) {
        let targetID = activeLineID ?? canonicalLineID
        let anchor: UnitPoint = activeLineID == nil ? .top : .center
        guard let targetID else { return }
        scrollCoordinator.prepareProgrammaticScroll(to: targetID)
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard scrollPhase == .idle,
                  (activeLineID ?? canonicalLineID) == targetID else {
                return
            }
            proxy.scrollTo(targetID, anchor: anchor)
        }
    }

    private func highlightedLine(_ line: ReaderLine) -> Text {
        guard line.sentenceID == activeSentenceID,
              let activeRange,
              let sentence = document.sentences.first(where: { $0.id == line.sentenceID }) else {
            return Text(line.text)
        }

        let displayRange = line.displayRange(for: activeRange, in: sentence.text)
        guard let displayRange else {
            return Text(line.text)
        }

        let lineText = line.text as NSString
        let prefix = lineText.substring(with: NSRange(location: 0, length: displayRange.location))
        let spoken = lineText.substring(with: displayRange)
        let suffixStart = NSMaxRange(displayRange)
        let suffixLength = lineText.length - suffixStart
        let suffix = suffixLength > 0
            ? lineText.substring(with: NSRange(location: suffixStart, length: suffixLength))
            : ""

        return Text(prefix)
            + Text(spoken)
                .fontWeight(.semibold)
                .underline(true, pattern: .solid)
            + Text(suffix)
    }
}

private struct ReaderContentsView: View {
    let model: ReaderModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(model.chapters) { chapter in
                        chapterRow(chapter)
                            .id(chapter.id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(ReadingTokens.canvas)
                .accessibilityIdentifier("reader-contents-list")
                .onAppear {
                    guard let currentChapterID = model.currentChapterID else { return }
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo(currentChapterID, anchor: .center)
                    }
                }
            }
            .navigationTitle("Contents")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityHint("Returns to the book.")
                    .accessibilityIdentifier("reader-contents-done")
                }
            }
        }
        .tint(ReadingTokens.ink)
        .background(ReadingTokens.canvas)
        .accessibilityIdentifier("reader-contents-sheet")
    }

    private func chapterRow(_ chapter: ReaderChapter) -> some View {
        let isCurrent = chapter.id == model.currentChapterID

        return Button {
            if model.jump(toChapterID: chapter.id) {
                dismiss()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(chapter.title)
                    .font(.body)
                    .foregroundStyle(ReadingTokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ReadingTokens.ink)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, indentation(for: chapter.level))
            .frame(maxWidth: .infinity, minHeight: ReadingTokens.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.navigationEnabled)
        .listRowBackground(ReadingTokens.canvas)
        .listRowSeparatorTint(ReadingTokens.hairline)
        .accessibilityLabel(chapter.title)
        .accessibilityValue(isCurrent ? "Current section" : "")
        .accessibilityHint("Moves to this section and returns to the book.")
        .accessibilityIdentifier("reader-contents-section-\(chapter.id)")
    }

    private func indentation(for level: Int) -> CGFloat {
        guard !dynamicTypeSize.isAccessibilitySize else { return 0 }
        return CGFloat(min(max(level, 0), 3)) * 16
    }
}
