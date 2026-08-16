import Foundation
import Observation

struct ReaderAppearance: Codable, Equatable, Sendable {
    enum TextSize: String, CaseIterable, Codable, Identifiable, Sendable {
        case small
        case book
        case large
        case extraLarge

        var id: String { rawValue }

        var label: String {
            switch self {
            case .small: "Small"
            case .book: "Book"
            case .large: "Large"
            case .extraLarge: "Extra large"
            }
        }

        var points: Double {
            switch self {
            case .small: 18
            case .book: 20
            case .large: 24
            case .extraLarge: 28
            }
        }
    }

    enum LineSpacing: String, CaseIterable, Codable, Identifiable, Sendable {
        case compact
        case comfortable
        case relaxed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .compact: "Compact"
            case .comfortable: "Comfortable"
            case .relaxed: "Relaxed"
            }
        }

        func points(for fontSize: Double) -> Double {
            switch self {
            case .compact: fontSize * 0.30
            case .comfortable: fontSize * 0.45
            case .relaxed: fontSize * 0.65
            }
        }
    }

    enum Margin: String, CaseIterable, Codable, Identifiable, Sendable {
        case narrow
        case standard
        case wide

        var id: String { rawValue }

        var label: String {
            switch self {
            case .narrow: "Narrow"
            case .standard: "Standard"
            case .wide: "Wide"
            }
        }

        var points: Double {
            switch self {
            case .narrow: 28
            case .standard: 48
            case .wide: 72
            }
        }
    }

    var textSize: TextSize
    var lineSpacing: LineSpacing
    var margin: Margin

    static let bookDefault = ReaderAppearance(
        textSize: .book,
        lineSpacing: .comfortable,
        margin: .standard
    )
}

@Observable
@MainActor
final class ReaderModel {
    let document: ReaderDocument
    let narration: NarrationModel
    private let layoutEngine = SentenceLayoutEngine()
    private let sentenceIndexByID: [String: Int]
    @ObservationIgnored private var cachedLayout: CachedLayout?
    private let onPositionChange: (ReaderPosition) -> Void
    private let onLinePresetChange: (SentenceLayoutEngine.LinePreset) -> Void
    private let onAppearanceChange: (ReaderAppearance) -> Void

    var position: ReaderPosition {
        didSet {
            if narration.position != position {
                narration.updatePosition(position)
            }
            if oldValue != position {
                onPositionChange(position)
            }
        }
    }
    var linePreset: SentenceLayoutEngine.LinePreset {
        didSet {
            if oldValue != linePreset {
                onLinePresetChange(linePreset)
            }
        }
    }
    var appearance: ReaderAppearance {
        didSet {
            if oldValue != appearance {
                onAppearanceChange(appearance)
            }
        }
    }
    var controlsVisible = false

    var navigationEnabled: Bool {
        narration.state != .speaking && narration.state != .paused
    }

    var showsNarrationBar: Bool {
        narration.state == .speaking || narration.state == .paused
    }

    var chapters: [ReaderChapter] {
        document.navigationChapters.filter {
            sentenceIndexByID[$0.startSentenceID] != nil
        }
    }

    var currentChapterID: String? {
        guard let currentIndex = sentenceIndexByID[position.sentenceID] else {
            return nil
        }
        return chapters.last { chapter in
            guard let chapterIndex = sentenceIndexByID[chapter.startSentenceID] else {
                return false
            }
            return chapterIndex <= currentIndex
        }?.id
    }

    var currentChapterTitle: String {
        guard let currentIndex = sentenceIndexByID[position.sentenceID] else {
            return document.chapterTitle
        }
        let rawChapterIDs = Set(document.chapters.map(\.id))
        return chapters.last { chapter in
            guard rawChapterIDs.contains(chapter.id),
                  chapter.level == 0,
                  let chapterIndex = sentenceIndexByID[chapter.startSentenceID] else {
                return false
            }
            return chapterIndex <= currentIndex
        }?.title ?? document.chapterTitle
    }

    init(
        document: ReaderDocument,
        speechEngine: SpeechEngine,
        initialPosition: ReaderPosition? = nil,
        initialLinePreset: SentenceLayoutEngine.LinePreset = .fullPage,
        initialAppearance: ReaderAppearance = .bookDefault,
        onPositionChange: @escaping (ReaderPosition) -> Void = { _ in },
        onLinePresetChange: @escaping (SentenceLayoutEngine.LinePreset) -> Void = { _ in },
        onAppearanceChange: @escaping (ReaderAppearance) -> Void = { _ in }
    ) {
        self.document = document
        self.sentenceIndexByID = Dictionary(
            uniqueKeysWithValues: document.sentences.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        self.onPositionChange = onPositionChange
        self.onLinePresetChange = onLinePresetChange
        self.onAppearanceChange = onAppearanceChange
        let firstSentenceID = document.sentences.first?.id ?? ""
        let resolvedPosition: ReaderPosition
        if let initialPosition,
           document.sentences.contains(where: { $0.id == initialPosition.sentenceID }) {
            resolvedPosition = initialPosition
        } else {
            resolvedPosition = ReaderPosition(sentenceID: firstSentenceID)
        }
        self.position = resolvedPosition
        self.linePreset = initialLinePreset
        self.appearance = initialAppearance
        self.narration = NarrationModel(
            document: document,
            position: resolvedPosition,
            engine: speechEngine
        )
        self.narration.onPositionChange = { [weak self] position in
            guard self?.position != position else { return }
            self?.position = position
        }
    }

    func window(width: Double, fontSize: Double) -> ReaderWindow {
        layoutEngine.makeWindow(
            lines: lines(width: width, fontSize: fontSize),
            position: position,
            preset: linePreset
        )
    }

    /// Keep the current spoken phrase inside a finite reading window and make
    /// the exact spoken line the shared reading/narration position.
    func revealActivePhrase(width: Double, fontSize: Double) {
        guard let sentenceID = narration.activeSentenceID,
              let activeRange = narration.activeRange else {
            return
        }

        guard let sentence = document.sentences.first(where: { $0.id == sentenceID }) else {
            return
        }
        let sentenceLines = layoutEngine.makeLines(
            sentence: sentence,
            width: width,
            fontSize: fontSize
        )
        guard let activeLineIndex = sentenceLines.firstIndex(where: {
            NSIntersectionRange($0.sourceRange, activeRange).length > 0
        }) else {
            return
        }

        let spokenPosition = ReaderPosition(
            sentenceID: sentenceID,
            rowOffset: activeLineIndex
        )
        guard spokenPosition != position else { return }
        position = spokenPosition
    }

    /// Show the controls sheet. Controls bind live to `linePreset`, so
    /// there is no draft to seed.
    func showControls() {
        controlsVisible = true
    }

    @discardableResult
    func startNarration() -> Bool {
        narration.start()
        guard narration.state == .speaking else { return false }
        controlsVisible = false
        return true
    }

    @discardableResult
    func stopForExit() -> Bool {
        guard narration.stopVoicePreview() else { return false }
        guard showsNarrationBar else { return true }
        narration.stop()
        return narration.state == .stopped
    }

    func select(preset: SentenceLayoutEngine.LinePreset) {
        linePreset = preset
        controlsVisible = false
    }

    /// Dismiss the controls sheet. Changes were already applied live.
    func cancel() {
        _ = narration.stopVoicePreview()
        controlsVisible = false
    }

    func advance(width: Double, fontSize: Double) {
        guard navigationEnabled else { return }
        move(by: 1, width: width, fontSize: fontSize)
    }

    func goBack(width: Double, fontSize: Double) {
        guard navigationEnabled else { return }
        move(by: -1, width: width, fontSize: fontSize)
    }

    func updatePosition(for lineID: String, in window: ReaderWindow) {
        guard navigationEnabled else { return }
        guard let lineIndex = window.lines.firstIndex(where: { $0.id == lineID }) else { return }
        let line = window.lines[lineIndex]
        let sentenceStart = window.lines[..<lineIndex].firstIndex { $0.sentenceID == line.sentenceID } ?? lineIndex
        position = ReaderPosition(
            sentenceID: line.sentenceID,
            rowOffset: lineIndex - sentenceStart
        )
    }

    func position(for lineID: String, width: Double, fontSize: Double) -> ReaderPosition? {
        let allLines = lines(width: width, fontSize: fontSize)
        guard let lineIndex = allLines.firstIndex(where: { $0.id == lineID }) else {
            return nil
        }
        let line = allLines[lineIndex]
        let sentenceStart = allLines.firstIndex {
            $0.sentenceID == line.sentenceID
        } ?? lineIndex
        return ReaderPosition(
            sentenceID: line.sentenceID,
            rowOffset: lineIndex - sentenceStart
        )
    }

    func position(
        forSentenceID sentenceID: String,
        sourceLocation: Int,
        width: Double,
        fontSize: Double
    ) -> ReaderPosition? {
        let allLines = lines(width: width, fontSize: fontSize)
        let sentenceLines = allLines.enumerated().filter {
            $0.element.sentenceID == sentenceID
        }
        guard let sentenceStart = sentenceLines.first?.offset else {
            return nil
        }
        let target = sentenceLines.first {
            sourceLocation >= $0.element.sourceRange.location &&
            sourceLocation < NSMaxRange($0.element.sourceRange)
        } ?? sentenceLines.last {
            $0.element.sourceRange.location <= sourceLocation
        } ?? sentenceLines.first
        guard let target else { return nil }
        return ReaderPosition(
            sentenceID: sentenceID,
            rowOffset: target.offset - sentenceStart
        )
    }

    @discardableResult
    func jump(toChapterID id: String) -> Bool {
        guard navigationEnabled,
              let chapter = chapters.first(where: { $0.id == id }),
              sentenceIndexByID[chapter.startSentenceID] != nil else {
            return false
        }
        position = ReaderPosition(
            sentenceID: chapter.startSentenceID,
            rowOffset: 0
        )
        return true
    }

    private func move(by direction: Int, width: Double, fontSize: Double) {
        let allLines = lines(width: width, fontSize: fontSize)
        guard !allLines.isEmpty,
              let sentenceStart = allLines.firstIndex(where: { $0.sentenceID == position.sentenceID }) else { return }

        let currentOffset = min(max(position.rowOffset, 0), allLines[sentenceStart...].prefix { $0.sentenceID == position.sentenceID }.count - 1)
        let currentIndex = sentenceStart + max(currentOffset, 0)
        let visibleCount = window(width: width, fontSize: fontSize).lines.count
        let pageSize = max(linePreset.lineCount ?? visibleCount, 1)
        let targetIndex: Int
        if direction > 0 {
            targetIndex = currentIndex + pageSize
            guard targetIndex < allLines.count else { return }
        } else {
            targetIndex = max(currentIndex - pageSize, 0)
        }

        let target = allLines[targetIndex]
        let targetSentenceStart = allLines.firstIndex { $0.sentenceID == target.sentenceID } ?? targetIndex
        position = ReaderPosition(
            sentenceID: target.sentenceID,
            rowOffset: targetIndex - targetSentenceStart
        )
    }

    private func lines(width: Double, fontSize: Double) -> [ReaderLine] {
        let key = LayoutKey(width: width, fontSize: fontSize)
        if cachedLayout?.key == key {
            return cachedLayout?.lines ?? []
        }
        let lines = layoutEngine.makeLines(
            document: document,
            width: width,
            fontSize: fontSize
        )
        cachedLayout = CachedLayout(key: key, lines: lines)
        return lines
    }

    private struct CachedLayout {
        let key: LayoutKey
        let lines: [ReaderLine]
    }

    private struct LayoutKey: Equatable {
        let widthEighths: Int
        let fontSizeEighths: Int

        init(width: Double, fontSize: Double) {
            widthEighths = Int((width * 8).rounded())
            fontSizeEighths = Int((fontSize * 8).rounded())
        }
    }
}

struct ReaderScrollCoordinator: Equatable {
    private enum Origin: Equatable {
        case idle
        case programmatic
        case user
    }

    private(set) var canonicalLineID: String?
    private var origin: Origin = .idle
    private var pendingVisibleLineID: String?

    @discardableResult
    mutating func prepareProgrammaticScroll(to lineID: String) -> Bool {
        let changed = canonicalLineID != lineID
        canonicalLineID = lineID
        origin = .programmatic
        pendingVisibleLineID = nil
        return changed
    }

    mutating func userInteractionBegan() {
        if origin != .user {
            pendingVisibleLineID = nil
        }
        origin = .user
    }

    mutating func observeVisibleLine(_ lineID: String?) {
        guard origin == .user, let lineID else { return }
        pendingVisibleLineID = lineID
    }

    mutating func finishUserScroll(
        finalVisibleLineID: String?,
        navigationEnabled: Bool
    ) -> String? {
        defer {
            origin = .idle
            pendingVisibleLineID = nil
        }
        guard origin == .user,
              navigationEnabled,
              let lineID = finalVisibleLineID ?? pendingVisibleLineID,
              lineID != canonicalLineID else {
            return nil
        }
        canonicalLineID = lineID
        return lineID
    }
}
