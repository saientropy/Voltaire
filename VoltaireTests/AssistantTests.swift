import Foundation
import Testing
@testable import Voltaire

struct AssistantTests {
    @Test func contextUsesStableSentenceAndOnlyImmediateNeighbors() {
        let document = assistantDocument
        let position = ReaderPosition(sentenceID: "sentence-2", rowOffset: 3)

        let context = AskContext(document: document, position: position)

        #expect(context?.currentSentenceID == "sentence-2")
        #expect(context?.previousSentence == "First sentence.")
        #expect(context?.currentSentence == "Second sentence.")
        #expect(context?.nextSentence == "Third sentence.")
        #expect(position == ReaderPosition(sentenceID: "sentence-2", rowOffset: 3))
    }

    @Test func contextHandlesFirstAndLastSentenceBoundaries() {
        let document = assistantDocument

        let first = AskContext(
            document: document,
            position: ReaderPosition(sentenceID: "sentence-1")
        )
        let last = AskContext(
            document: document,
            position: ReaderPosition(sentenceID: "sentence-4")
        )

        #expect(first?.previousSentence == nil)
        #expect(first?.nextSentence == "Second sentence.")
        #expect(last?.previousSentence == "Third sentence.")
        #expect(last?.nextSentence == nil)
    }

    @Test func contextUsesTheCurrentChapterTitle() {
        let first = AskContext(
            document: assistantDocument,
            position: ReaderPosition(sentenceID: "sentence-2")
        )
        let second = AskContext(
            document: assistantDocument,
            position: ReaderPosition(sentenceID: "sentence-4")
        )

        #expect(first?.chapterTitle == "Chapter One")
        #expect(second?.chapterTitle == "Chapter Two")
    }

    @Test func promptContainsOnlyTheImmediatePassageAndRequest() {
        let context = AskContext(
            document: assistantDocument,
            position: ReaderPosition(sentenceID: "sentence-2")
        )!

        let prompt = context.prompt(for: .explain)

        #expect(prompt.contains("[Previous] First sentence."))
        #expect(prompt.contains("[Current] Second sentence."))
        #expect(prompt.contains("[Next] Third sentence."))
        #expect(prompt.contains(AskAction.explain.request))
        #expect(!prompt.contains("Fourth sentence."))
    }

    @Test func customQuestionTrimsRejectsEmptyAndCapsLength() {
        #expect(AskAction.customRequest("  \n ") == nil)
        #expect(AskAction.customRequest("  What does this imply?  ")?.request == "What does this imply?")
        #expect(AskAction.customRequest(String(repeating: "x", count: 400))?.request.count == 300)
    }

    @Test func terminalAskStatesChooseTheirAccessibleResult() {
        #expect(AskPhase.ready.accessibilityTarget == nil)
        #expect(AskPhase.responding.accessibilityTarget == nil)
        #expect(AskPhase.response("Answer").accessibilityTarget == .response)
        #expect(AskPhase.unavailable(.modelNotReady).accessibilityTarget == .unavailable)
        #expect(AskPhase.failed(.busy).accessibilityTarget == .failure)
    }

    @Test @MainActor func unavailableModelNeverCallsAnswer() async {
        let service = FakeAssistantService(availability: .modelNotReady, result: .success("unused"))
        let model = AskModel(service: service)
        let context = AskContext(
            document: assistantDocument,
            position: ReaderPosition(sentenceID: "sentence-2")
        )!

        model.present(context: context)
        model.submit(.explain)

        #expect(model.phase == .unavailable(.modelNotReady))
        #expect(AssistantAvailability.modelNotReady.userMessage.contains("preparing"))
        #expect(await service.callCount == 0)
    }

    @Test @MainActor func cancellingAnUnavailableSheetDoesNotPretendTheModelIsReady() {
        let service = FakeAssistantService(
            availability: .modelNotReady,
            result: .success("unused")
        )
        let model = AskModel(service: service)
        model.present(context: AskContext(
            document: assistantDocument,
            position: ReaderPosition(sentenceID: "sentence-2")
        )!)

        model.cancelRequest()

        #expect(model.phase == .unavailable(.modelNotReady))
        #expect(model.isPresented)
    }

    @Test @MainActor func successfulAnswerIsTrimmedAndDoesNotMoveReaderState() async {
        let service = FakeAssistantService(availability: .available, result: .success("  A short answer.  \n"))
        let model = AskModel(service: service)
        let reader = ReaderModel(
            document: assistantDocument,
            speechEngine: RefusingSpeechEngine(),
            initialPosition: ReaderPosition(sentenceID: "sentence-2", rowOffset: 1),
            initialLinePreset: .lines(6)
        )
        let originalPosition = reader.position
        let originalPreset = reader.linePreset
        model.present(context: AskContext(document: reader.document, position: reader.position)!)

        model.submit(.explain)
        await waitForSettledPhase(model)

        #expect(model.phase == .response("A short answer."))
        #expect(reader.position == originalPosition)
        #expect(reader.linePreset == originalPreset)
    }

    @Test @MainActor func requestErrorsBecomePlainFailureStates() async {
        let service = FakeAssistantService(availability: .available, result: .failure(.busy))
        let model = AskModel(service: service)
        model.present(context: AskContext(
            document: assistantDocument,
            position: ReaderPosition(sentenceID: "sentence-2")
        )!)

        model.submit(.simplify)
        await waitForSettledPhase(model)

        #expect(model.phase == .failed(.busy))
        #expect(AssistantRequestError.busy.userMessage.contains("busy"))
    }

    @Test @MainActor func newerRequestWinsWhenOlderProviderIgnoresCancellation() async {
        let service = ControlledAssistantService()
        let model = AskModel(service: service)
        model.present(context: AskContext(
            document: assistantDocument,
            position: ReaderPosition(sentenceID: "sentence-2")
        )!)

        model.submit(.explain)
        await service.waitUntilPending(.explain)
        model.submit(.simplify)
        await service.waitUntilPending(.simplify)

        await service.resume(.simplify, with: "New answer")
        await waitForSettledPhase(model)
        #expect(model.phase == .response("New answer"))

        await service.resume(.explain, with: "Stale answer")
        for _ in 0..<10 { await Task.yield() }
        #expect(model.phase == .response("New answer"))
    }

    @Test @MainActor func dismissPreventsALateAnswerFromReopeningTheSheet() async {
        let service = ControlledAssistantService()
        let model = AskModel(service: service)
        model.present(context: AskContext(
            document: assistantDocument,
            position: ReaderPosition(sentenceID: "sentence-2")
        )!)
        model.submit(.explain)
        await service.waitUntilPending(.explain)

        model.dismiss()
        await service.resume(.explain, with: "Late answer")
        for _ in 0..<10 { await Task.yield() }

        #expect(model.isPresented == false)
        #expect(model.context == nil)
        #expect(model.phase == .ready)
    }

    @MainActor
    private func waitForSettledPhase(_ model: AskModel) async {
        for _ in 0..<100 {
            if model.phase != .responding { return }
            await Task.yield()
        }
    }

    private var assistantDocument: ReaderDocument {
        ReaderDocument(
            id: "assistant-book",
            title: "Test Book",
            author: "Test Author",
            chapterTitle: "Chapter One",
            sentences: [
                ReaderSentence(id: "sentence-1", text: "First sentence."),
                ReaderSentence(id: "sentence-2", text: "Second sentence."),
                ReaderSentence(id: "sentence-3", text: "Third sentence."),
                ReaderSentence(id: "sentence-4", text: "Fourth sentence.")
            ],
            chapters: [
                ReaderChapter(
                    id: "assistant-chapter-one",
                    title: "Chapter One",
                    startSentenceID: "sentence-1"
                ),
                ReaderChapter(
                    id: "assistant-chapter-two",
                    title: "Chapter Two",
                    startSentenceID: "sentence-4"
                )
            ]
        )
    }
}

private actor FakeAssistantService: AssistantService {
    nonisolated let reportedAvailability: AssistantAvailability
    private let result: Result<String, AssistantRequestError>
    private(set) var callCount = 0

    init(
        availability: AssistantAvailability,
        result: Result<String, AssistantRequestError>
    ) {
        reportedAvailability = availability
        self.result = result
    }

    nonisolated func availability() -> AssistantAvailability {
        reportedAvailability
    }

    func answer(action: AskAction, context: AskContext) async throws -> String {
        callCount += 1
        return try result.get()
    }
}

private actor ControlledAssistantService: AssistantService {
    nonisolated func availability() -> AssistantAvailability { .available }

    private var continuations: [AskAction: CheckedContinuation<String, Never>] = [:]

    func answer(action: AskAction, context: AskContext) async throws -> String {
        await withCheckedContinuation { continuation in
            continuations[action] = continuation
        }
    }

    func waitUntilPending(_ action: AskAction) async {
        while continuations[action] == nil {
            await Task.yield()
        }
    }

    func resume(_ action: AskAction, with answer: String) {
        continuations.removeValue(forKey: action)?.resume(returning: answer)
    }
}

private final class RefusingSpeechEngine: SpeechEngine {
    var onEvent: ((SpeechEvent) -> Void)?
    func speak(_ utterances: [SpeechUtterance]) -> Bool { false }
    func pause() -> Bool { false }
    func resume() -> Bool { false }
    func stop() -> Bool { false }
}
