import Foundation
import Observation
import Testing
@testable import Voltaire

@MainActor
struct ReaderPositionTests {
    @Test func scrollCoordinatorReanchorsOnFullPageEntryAndIgnoresProgrammaticFollow() {
        var coordinator = ReaderScrollCoordinator()
        coordinator.prepareProgrammaticScroll(to: "line-007")
        coordinator.observeVisibleLine("line-012")

        #expect(coordinator.canonicalLineID == "line-007")
        #expect(coordinator.finishUserScroll(
            finalVisibleLineID: "line-012",
            navigationEnabled: true
        ) == nil)
        #expect(coordinator.canonicalLineID == "line-007")
    }

    @Test func scrollCoordinatorAcceptsGenuineUserPositionChanges() {
        var coordinator = ReaderScrollCoordinator()
        coordinator.prepareProgrammaticScroll(to: "line-007")
        coordinator.userInteractionBegan()
        coordinator.observeVisibleLine("line-010")
        coordinator.observeVisibleLine("line-011")

        #expect(coordinator.finishUserScroll(
            finalVisibleLineID: "line-012",
            navigationEnabled: true
        ) == "line-012")
        #expect(coordinator.canonicalLineID == "line-012")
    }

    @Test func scrollCoordinatorStopsAcceptingVisibilityAfterUserScrollEnds() {
        var coordinator = ReaderScrollCoordinator()
        coordinator.prepareProgrammaticScroll(to: "line-007")
        coordinator.userInteractionBegan()
        #expect(coordinator.finishUserScroll(
            finalVisibleLineID: "line-012",
            navigationEnabled: true
        ) == "line-012")

        coordinator.observeVisibleLine("line-018")

        #expect(coordinator.finishUserScroll(
            finalVisibleLineID: nil,
            navigationEnabled: true
        ) == nil)
        #expect(coordinator.canonicalLineID == "line-012")
    }

    @Test func programmaticReanchorCancelsAnActiveUserScrollSession() {
        var coordinator = ReaderScrollCoordinator()
        coordinator.userInteractionBegan()
        coordinator.observeVisibleLine("line-019")

        coordinator.prepareProgrammaticScroll(to: "line-020")

        #expect(coordinator.finishUserScroll(
            finalVisibleLineID: "line-021",
            navigationEnabled: true
        ) == nil)
        #expect(coordinator.canonicalLineID == "line-020")
    }

    @Test func userFullPageScrollUpdatesExactPositionAndPersistsOnce() throws {
        let document = makeLongScrollDocument(id: "scroll-persistence")
        var savedPositions: [ReaderPosition] = []
        let model = ReaderModel(
            document: document,
            speechEngine: SilentSpeechEngine(),
            onPositionChange: { savedPositions.append($0) }
        )
        let window = model.window(width: 180, fontSize: 20)
        let secondSentenceLines = window.lines.filter { $0.sentenceID == "scroll-2" }
        let targetLine = try #require(secondSentenceLines.dropFirst(2).first)
        var coordinator = ReaderScrollCoordinator()
        coordinator.prepareProgrammaticScroll(to: window.anchorLineID)
        coordinator.userInteractionBegan()
        coordinator.observeVisibleLine(targetLine.id)

        let accepted = coordinator.finishUserScroll(
            finalVisibleLineID: nil,
            navigationEnabled: model.navigationEnabled
        )
        let acceptedLineID = try #require(accepted)
        model.updatePosition(for: acceptedLineID, in: window)

        let expected = ReaderPosition(sentenceID: "scroll-2", rowOffset: 2)
        #expect(model.position == expected)
        #expect(model.narration.position == expected)
        #expect(savedPositions == [expected])

        coordinator.userInteractionBegan()
        #expect(coordinator.finishUserScroll(
            finalVisibleLineID: targetLine.id,
            navigationEnabled: model.navigationEnabled
        ) == nil)
        #expect(savedPositions == [expected])
    }

    @Test func readerStartsAtTheFirstStableSentence() {
        let model = makeReaderModel()
        #expect(model.position.sentenceID == "candide-001")
    }

    @Test func contentsJumpUsesStableSentenceAndPersistsOnce() throws {
        let document = makeChapteredDocument()
        var savedPositions: [ReaderPosition] = []
        let model = ReaderModel(
            document: document,
            speechEngine: SilentSpeechEngine(),
            initialPosition: ReaderPosition(sentenceID: "chapter-001", rowOffset: 1),
            onPositionChange: { savedPositions.append($0) }
        )
        let secondChapter = try #require(
            model.chapters.first { $0.title == "Chapter Two" }
        )

        #expect(model.currentChapterTitle == "Chapter One")
        #expect(model.jump(toChapterID: secondChapter.id))

        let expected = ReaderPosition(sentenceID: "chapter-003", rowOffset: 0)
        #expect(model.position == expected)
        #expect(model.narration.position == expected)
        #expect(model.currentChapterID == secondChapter.id)
        #expect(model.currentChapterTitle == "Chapter Two")
        #expect(savedPositions == [expected])
        #expect(model.window(width: 260, fontSize: 20).anchoredSentenceID == "chapter-003")
        #expect(model.window(width: 720, fontSize: 28).anchoredSentenceID == "chapter-003")
    }

    @Test func contentsJumpRejectsUnknownTargetWithoutMoving() {
        let model = makeReaderModel(document: makeChapteredDocument())
        let start = model.position

        #expect(!model.jump(toChapterID: "missing-chapter"))
        #expect(model.position == start)
        #expect(model.narration.position == start)
    }

    @Test func contentsJumpIsRefusedWhileNarrationIsSpeakingOrPaused() throws {
        let document = makeChapteredDocument()
        let engine = ControllableSpeechEngine()
        let model = ReaderModel(document: document, speechEngine: engine)
        let secondChapter = try #require(
            model.chapters.first { $0.title == "Chapter Two" }
        )

        model.narration.start()
        #expect(model.narration.state == .speaking)
        #expect(!model.jump(toChapterID: secondChapter.id))
        #expect(model.position.sentenceID == "chapter-001")

        model.narration.pause()
        #expect(model.narration.state == .paused)
        #expect(!model.jump(toChapterID: secondChapter.id))
        #expect(model.position.sentenceID == "chapter-001")
    }

    @Test func currentChapterTracksCanonicalSentenceBoundaries() {
        let model = makeReaderModel(document: makeChapteredDocument())

        #expect(model.currentChapterTitle == "Chapter One")
        model.position = ReaderPosition(sentenceID: "chapter-002")
        #expect(model.currentChapterTitle == "Chapter One")
        model.position = ReaderPosition(sentenceID: "chapter-003")
        #expect(model.currentChapterTitle == "Chapter Two")
        model.position = ReaderPosition(sentenceID: "chapter-004")
        #expect(model.currentChapterTitle == "Chapter Two")
    }

    @Test func persistentHeaderUsesRealTopLevelChapterInsteadOfStartOrNestedSubtitle() {
        let document = ReaderDocument(
            id: "nested-chapters",
            title: "Nested Chapters",
            author: "Voltaire Tests",
            chapterTitle: "Front matter",
            sentences: [
                ReaderSentence(id: "nested-001", text: "Publisher's note."),
                ReaderSentence(id: "nested-002", text: "Chapter One"),
                ReaderSentence(id: "nested-003", text: "A very long descriptive subtitle."),
                ReaderSentence(id: "nested-004", text: "The chapter continues.")
            ],
            chapters: [
                ReaderChapter(
                    id: "nested-section-one",
                    title: "Chapter One",
                    startSentenceID: "nested-002"
                ),
                ReaderChapter(
                    id: "nested-subtitle-one",
                    title: "A very long descriptive subtitle",
                    level: 1,
                    startSentenceID: "nested-003"
                )
            ]
        )
        let model = makeReaderModel(document: document)

        #expect(model.currentChapterTitle == "Front matter")
        model.position = ReaderPosition(sentenceID: "nested-002")
        #expect(model.currentChapterTitle == "Chapter One")
        model.position = ReaderPosition(sentenceID: "nested-003")
        #expect(model.currentChapterID == "nested-subtitle-one")
        #expect(model.currentChapterTitle == "Chapter One")
        model.position = ReaderPosition(sentenceID: "nested-004")
        #expect(model.currentChapterTitle == "Chapter One")
    }

    @Test func showControlsPreservesCanonicalPositionAndLinePreset() {
        let model = makeReaderModel()
        model.position = ReaderPosition(sentenceID: "candide-009", rowOffset: 1)
        model.linePreset = .lines(7)
        let position = model.position

        model.showControls()

        #expect(model.controlsVisible == true)
        #expect(model.position == position)
        #expect(model.linePreset == .lines(7))
    }

    @Test func layoutInputsDoNotChangeCanonicalPosition() {
        let model = makeReaderModel()
        model.position = ReaderPosition(sentenceID: "candide-010")
        _ = model.window(width: 320, fontSize: 18)
        model.select(preset: .lines(3))
        _ = model.window(width: 760, fontSize: 24)

        #expect(model.position.sentenceID == "candide-010")
        #expect(model.position.rowOffset == 0)
    }

    @Test func appearanceChangesPreservePositionNarrationAndLineWindow() {
        var savedAppearances: [ReaderAppearance] = []
        let initialPosition = ReaderPosition(sentenceID: "candide-009", rowOffset: 1)
        let model = ReaderModel(
            document: SampleChapter.document,
            speechEngine: SilentSpeechEngine(),
            initialPosition: initialPosition,
            initialLinePreset: .lines(7),
            onAppearanceChange: { savedAppearances.append($0) }
        )
        let changed = ReaderAppearance(
            textSize: .extraLarge,
            lineSpacing: .relaxed,
            margin: .wide
        )

        model.appearance = changed
        model.appearance = changed

        #expect(model.position == initialPosition)
        #expect(model.narration.position == initialPosition)
        #expect(model.linePreset == .lines(7))
        #expect(savedAppearances == [changed])
    }

    @Test func everyAppearanceLayoutStaysAnchoredToTheCanonicalSentence() {
        let model = makeReaderModel()
        model.position = ReaderPosition(sentenceID: "candide-009")

        for size in ReaderAppearance.TextSize.allCases {
            for margin in ReaderAppearance.Margin.allCases {
                model.appearance = ReaderAppearance(
                    textSize: size,
                    lineSpacing: .comfortable,
                    margin: margin
                )
                let width = max(700 - margin.points * 2, 280)
                let window = model.window(width: width, fontSize: size.points)
                #expect(window.anchoredSentenceID == "candide-009")
            }
        }

        #expect(model.position.sentenceID == "candide-009")
        #expect(model.narration.position.sentenceID == "candide-009")
    }

    @Test func fullPageWindowAnchorsToCanonicalSentenceAndRequestedRow() {
        let engine = SentenceLayoutEngine()
        let allLines = engine.makeLines(document: SampleChapter.document, width: 240, fontSize: 20)
        let sentenceLines = allLines.filter { $0.sentenceID == "candide-009" }
        let rowOffset = min(1, max(sentenceLines.count - 1, 0))
        let position = ReaderPosition(sentenceID: "candide-009", rowOffset: rowOffset)

        let window = engine.makeWindow(
            document: SampleChapter.document,
            position: position,
            width: 240,
            fontSize: 20,
            preset: .fullPage
        )

        #expect(window.anchoredSentenceID == "candide-009")
        #expect(window.anchorLineID == sentenceLines[rowOffset].id)
        #expect(window.anchorLineID != allLines[0].id)
    }

    @Test func limitedReaderPagesLongSentencesWithoutSkippingRows() {
        let document = ReaderDocument(
            id: "paging",
            title: "Paging",
            author: "Test",
            chapterTitle: "Test",
            sentences: [
                ReaderSentence(id: "long", text: String(repeating: "long word ", count: 20)),
                ReaderSentence(id: "last", text: "The final sentence.")
            ]
        )
        let model = makeReaderModel(document: document)
        model.select(preset: .lines(3))
        let engine = SentenceLayoutEngine()
        let expected = engine.makeLines(document: document, width: 240, fontSize: 20).map(\.id)
        var collected: [String] = []
        var starts: [Int] = []

        for _ in 0..<20 {
            let page = model.window(width: 240, fontSize: 20)
            collected.append(contentsOf: page.lines.map(\.id))
            starts.append(model.position.rowOffset)
            let before = model.position
            model.advance(width: 240, fontSize: 20)
            if model.position == before { break }
        }

        #expect(collected == expected)
        #expect(starts.first == 0)
        #expect(starts.count == Int(ceil(Double(expected.count) / 3.0)))
    }

    @Test func everyFinitePresetCoversEveryLayoutLineExactlyOnce() {
        let document = ReaderDocument(
            id: "finite-pagination",
            title: "Finite Pagination",
            author: "Test",
            chapterTitle: "Chapter",
            sentences: (0..<8).map { index in
                ReaderSentence(
                    id: "finite-\(index)",
                    text: String(repeating: "Every selected line must remain reachable in order. ", count: 12)
                )
            }
        )
        let engine = SentenceLayoutEngine()

        for lineCount in 3...20 {
            for width in [280.0, 420.0, 760.0] {
                for fontSize in [18.0, 28.0, 56.0] {
                    let expected = engine
                        .makeLines(document: document, width: width, fontSize: fontSize)
                        .map(\.id)
                    let model = makeReaderModel(document: document)
                    model.select(preset: .lines(lineCount))
                    var actual: [String] = []
                    var stopped = false

                    for _ in 0...expected.count {
                        actual.append(contentsOf: model
                            .window(width: width, fontSize: fontSize)
                            .lines
                            .map(\.id))
                        let before = model.position
                        model.advance(width: width, fontSize: fontSize)
                        if model.position == before {
                            stopped = true
                            break
                        }
                    }

                    #expect(stopped)
                    #expect(actual == expected)
                    #expect(Set(actual).count == actual.count)
                }
            }
        }
    }

    @Test func finiteOverflowVisibleLineResolvesToExactPersistedPosition() throws {
        let document = makeLongScrollDocument(id: "finite-overflow-position")
        var savedPositions: [ReaderPosition] = []
        let model = ReaderModel(
            document: document,
            speechEngine: SilentSpeechEngine(),
            onPositionChange: { savedPositions.append($0) }
        )
        model.select(preset: .lines(20))
        let width = 180.0
        let fontSize = 56.0
        let allLines = SentenceLayoutEngine().makeLines(
            document: document,
            width: width,
            fontSize: fontSize
        )
        let window = model.window(width: width, fontSize: fontSize)
        let target = try #require(window.lines.dropFirst(8).first)
        let targetIndex = try #require(allLines.firstIndex { $0.id == target.id })
        let sentenceStart = try #require(
            allLines.firstIndex { $0.sentenceID == target.sentenceID }
        )
        let expected = ReaderPosition(
            sentenceID: target.sentenceID,
            rowOffset: targetIndex - sentenceStart
        )

        let resolved = try #require(
            model.position(for: target.id, width: width, fontSize: fontSize)
        )
        #expect(resolved == expected)

        model.position = resolved

        #expect(model.position == expected)
        #expect(model.narration.position == expected)
        #expect(savedPositions == [expected])
        #expect(model.window(width: width, fontSize: fontSize).anchorLineID == target.id)
    }

    @Test func finiteOverflowSourceAnchorSurvivesReflowBeforeCommit() throws {
        let document = makeLongScrollDocument(id: "finite-overflow-reflow")
        let model = ReaderModel(
            document: document,
            speechEngine: SilentSpeechEngine()
        )
        model.select(preset: .lines(20))

        let oldWidth = 180.0
        let newWidth = 420.0
        let fontSize = 56.0
        let oldWindow = model.window(width: oldWidth, fontSize: fontSize)
        let oldTarget = try #require(oldWindow.lines.dropFirst(8).first)
        let sourceLocation = oldTarget.sourceRange.location

        let reflowedPosition = try #require(
            model.position(
                forSentenceID: oldTarget.sentenceID,
                sourceLocation: sourceLocation,
                width: newWidth,
                fontSize: fontSize
            )
        )
        model.position = reflowedPosition

        let newWindow = model.window(width: newWidth, fontSize: fontSize)
        let newAnchor = try #require(
            newWindow.lines.first { $0.id == newWindow.anchorLineID }
        )
        #expect(newAnchor.sentenceID == oldTarget.sentenceID)
        #expect(newAnchor.sourceRange.location <= sourceLocation)
        #expect(NSMaxRange(newAnchor.sourceRange) > sourceLocation)
    }

    @Test func forwardAndBackReturnToTheSameTransientCursor() {
        let model = makeReaderModel()
        model.select(preset: .lines(3))
        let start = model.position

        model.advance(width: 240, fontSize: 20)
        let next = model.position
        model.goBack(width: 240, fontSize: 20)

        #expect(next != start)
        #expect(model.position == start)
    }

    @Test func selectingAPresetDismissesControlsAndKeepsPosition() {
        let model = makeReaderModel()
        model.position = ReaderPosition(sentenceID: "candide-007")
        model.controlsVisible = true

        model.select(preset: .lines(7))

        #expect(model.controlsVisible == false)
        #expect(model.linePreset == .lines(7))
        #expect(model.position.sentenceID == "candide-007")
        #expect(model.position.rowOffset == 0)
    }

    @Test func cancelDismissesControlsWithoutChangingPreset() {
        let model = makeReaderModel()
        model.select(preset: .lines(12))
        model.controlsVisible = true

        model.cancel()

        #expect(model.controlsVisible == false)
        #expect(model.linePreset == .lines(12))
    }

    @Test func cancelPreservesPositionAndFullPagePreset() {
        let model = makeReaderModel()
        model.position = ReaderPosition(sentenceID: "candide-005")
        model.controlsVisible = true

        model.cancel()

        #expect(model.controlsVisible == false)
        #expect(model.linePreset == .fullPage)
        #expect(model.position.sentenceID == "candide-005")
    }

    @Test func fullPageToLinesPreservesPosition() {
        let model = makeReaderModel()
        model.position = ReaderPosition(sentenceID: "candide-007")
        model.linePreset = .fullPage

        // Simulate the mode button switching to a line window.
        model.linePreset = .lines(model.linePreset.lineCount ?? 5)

        #expect(model.linePreset == .lines(5))
        #expect(model.position.sentenceID == "candide-007")
        #expect(model.position.rowOffset == 0)

        let window = model.window(width: 400, fontSize: 20)
        #expect(window.anchoredSentenceID == "candide-007")
    }

    @Test func exactThreeLinesPreservesPosition() {
        let model = makeReaderModel()
        model.position = ReaderPosition(sentenceID: "candide-004")
        model.linePreset = .lines(3)

        let window = model.window(width: 400, fontSize: 20)

        #expect(model.linePreset == .lines(3))
        #expect(window.lines.count == 3)
        #expect(window.anchoredSentenceID == "candide-004")
    }

    @Test func exactTwentyLinesPreservesPosition() {
        let model = makeReaderModel()
        model.position = ReaderPosition(sentenceID: "candide-004")
        model.linePreset = .lines(20)

        let window = model.window(width: 700, fontSize: 20)

        #expect(model.linePreset == .lines(20))
        #expect(window.anchoredSentenceID == "candide-004")
    }

    @Test func linesToFullPagePreservesPosition() {
        let model = makeReaderModel()
        model.position = ReaderPosition(sentenceID: "candide-009")
        model.linePreset = .lines(7)

        // Simulate the mode button switching to full page.
        model.linePreset = .fullPage

        #expect(model.linePreset == .fullPage)
        #expect(model.position.sentenceID == "candide-009")
        #expect(model.position.rowOffset == 0)

        let window = model.window(width: 400, fontSize: 20)
        #expect(window.anchoredSentenceID == "candide-009")
    }
}

@MainActor
struct AppNavigationTests {
    @Test func openingAndClosingASavedBookUsesAStableRoute() {
        let appModel = AppModel()

        appModel.openSample()
        #expect(appModel.path == [
            .reader(documentID: SampleChapter.document.id)
        ])

        appModel.closeReader()
        #expect(appModel.path.isEmpty)
    }

    @Test func unknownBookIDDoesNotCreateADeadRoute() {
        let appModel = AppModel()

        appModel.open(documentID: "missing-book")

        #expect(appModel.path.isEmpty)
    }

    @Test func readingPositionAndWindowPersistAcrossAppModelInstances() throws {
        let suiteName = "VoltaireTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = LibraryRepository(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let savedPosition = ReaderPosition(sentenceID: "candide-009", rowOffset: 2)
        let savedAppearance = ReaderAppearance(
            textSize: .large,
            lineSpacing: .relaxed,
            margin: .narrow
        )

        let first = AppModel(repository: repository, defaults: defaults)
        first.savePosition(savedPosition, for: SampleChapter.document.id)
        first.saveLinePreset(.lines(9), for: SampleChapter.document.id)
        first.saveReaderAppearance(savedAppearance)

        let reopened = AppModel(repository: repository, defaults: defaults)
        #expect(reopened.position(for: SampleChapter.document) == savedPosition)
        #expect(reopened.linePreset(for: SampleChapter.document.id) == .lines(9))
        #expect(reopened.readerAppearance() == savedAppearance)
    }

    @Test func savedPositionImmediatelyRefreshesLibraryProgress() throws {
        let suiteName = "VoltaireTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = LibraryRepository(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let appModel = AppModel(repository: repository, defaults: defaults)
        let savedPosition = ReaderPosition(sentenceID: "candide-009", rowOffset: 0)
        let observation = ObservationChangeRecorder()

        #expect(appModel.progressLabel(for: SampleChapter.document) == "New")
        withObservationTracking {
            _ = appModel.progressLabel(for: SampleChapter.document)
        } onChange: {
            observation.recordChange()
        }

        appModel.savePosition(savedPosition, for: SampleChapter.document.id)

        #expect(observation.didChange)
        #expect(appModel.savedPositions[SampleChapter.document.id] == savedPosition)
        #expect(appModel.progressLabel(for: SampleChapter.document) != "New")
    }

    @Test func missingOrCorruptAppearanceUsesBookDefaults() throws {
        let suiteName = "VoltaireTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = LibraryRepository(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let appModel = AppModel(repository: repository, defaults: defaults)

        #expect(appModel.readerAppearance() == .bookDefault)

        defaults.set(Data("not-json".utf8), forKey: "reader.appearance")

        #expect(appModel.readerAppearance() == .bookDefault)
    }

    @Test func importedFullPageScrollPositionPersistsAcrossAppModelInstances() throws {
        let suiteName = "VoltaireTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let repository = LibraryRepository(rootURL: rootURL)
        let document = makeLongScrollDocument(id: String(repeating: "a", count: 64))
        let first = AppModel(
            documents: [document],
            repository: repository,
            defaults: defaults
        )
        let reader = ReaderModel(
            document: document,
            speechEngine: SilentSpeechEngine(),
            initialPosition: first.position(for: document),
            onPositionChange: { first.savePosition($0, for: document.id) }
        )
        let window = reader.window(width: 180, fontSize: 20)
        let targetLine = try #require(
            window.lines.filter { $0.sentenceID == "scroll-2" }.dropFirst(2).first
        )
        var coordinator = ReaderScrollCoordinator()
        coordinator.prepareProgrammaticScroll(to: window.anchorLineID)
        coordinator.userInteractionBegan()
        let accepted = coordinator.finishUserScroll(
            finalVisibleLineID: targetLine.id,
            navigationEnabled: reader.navigationEnabled
        )
        let acceptedLineID = try #require(accepted)
        reader.updatePosition(for: acceptedLineID, in: window)

        let reopened = AppModel(
            documents: [document],
            repository: repository,
            defaults: defaults
        )
        let restored = reopened.position(for: document)
        let reopenedReader = ReaderModel(
            document: document,
            speechEngine: SilentSpeechEngine(),
            initialPosition: restored
        )

        #expect(restored == ReaderPosition(sentenceID: "scroll-2", rowOffset: 2))
        #expect(reopenedReader.window(width: 180, fontSize: 20).anchorLineID == targetLine.id)
    }
}

private final class ObservationChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false

    var didChange: Bool {
        lock.withLock { changed }
    }

    func recordChange() {
        lock.withLock {
            changed = true
        }
    }
}

@MainActor
private func makeReaderModel(document: ReaderDocument = SampleChapter.document) -> ReaderModel {
    ReaderModel(document: document, speechEngine: SilentSpeechEngine())
}

private func makeLongScrollDocument(id: String) -> ReaderDocument {
    ReaderDocument(
        id: id,
        title: "Scroll Test",
        author: "Voltaire Tests",
        chapterTitle: "A Long Chapter",
        sentences: [
            ReaderSentence(id: "scroll-1", text: "An opening sentence."),
            ReaderSentence(
                id: "scroll-2",
                text: String(repeating: "These words make a reliably long reading passage. ", count: 32)
            )
        ]
    )
}

private func makeChapteredDocument() -> ReaderDocument {
    ReaderDocument(
        id: "chaptered-book",
        title: "Chaptered Book",
        author: "Voltaire Tests",
        chapterTitle: "Chapter One",
        sentences: [
            ReaderSentence(id: "chapter-001", text: "Chapter One"),
            ReaderSentence(id: "chapter-002", text: "The first chapter continues."),
            ReaderSentence(id: "chapter-003", text: "Chapter Two"),
            ReaderSentence(id: "chapter-004", text: "The second chapter continues.")
        ],
        chapters: [
            ReaderChapter(
                id: "section-one",
                title: "Chapter One",
                startSentenceID: "chapter-001"
            ),
            ReaderChapter(
                id: "section-two",
                title: "Chapter Two",
                startSentenceID: "chapter-003"
            )
        ]
    )
}

private final class SilentSpeechEngine: SpeechEngine {
    var onEvent: ((SpeechEvent) -> Void)?

    func speak(_ utterances: [SpeechUtterance]) -> Bool { false }
    func pause() -> Bool { false }
    func resume() -> Bool { false }
    func stop() -> Bool { false }
}

private final class ControllableSpeechEngine: SpeechEngine {
    var onEvent: ((SpeechEvent) -> Void)?

    func speak(_ utterances: [SpeechUtterance]) -> Bool { utterances.count == 1 }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() -> Bool { true }
}
