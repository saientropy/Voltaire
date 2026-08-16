import Foundation

enum AssistantAvailability: Equatable, Sendable {
    case available
    case requiresIPadOS26
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case temporarilyUnavailable

    var userMessage: String {
        switch self {
        case .available:
            "Ready on this iPad."
        case .requiresIPadOS26:
            "Ask needs iPadOS 26 or later. Reading and narration still work normally."
        case .deviceNotEligible:
            "This iPad cannot run Apple's on-device reading assistant. Reading and narration still work normally."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings, then try Ask again."
        case .modelNotReady:
            "Apple Intelligence is still preparing its on-device model. Try Ask again when it finishes."
        case .temporarilyUnavailable:
            "The on-device reading assistant is temporarily unavailable. Try again in a moment."
        }
    }
}

enum AssistantRequestError: Error, Equatable, Sendable {
    case unavailable(AssistantAvailability)
    case unsupportedLanguage
    case contextTooLarge
    case busy
    case couldNotAnswer
    case emptyResponse
    case failed

    var userMessage: String {
        switch self {
        case let .unavailable(availability):
            availability.userMessage
        case .unsupportedLanguage:
            "The on-device model cannot answer in this language yet."
        case .contextTooLarge:
            "That passage is too long for a short answer. Move to a smaller passage and try again."
        case .busy:
            "The on-device model is busy. Try again in a moment."
        case .couldNotAnswer:
            "The on-device model could not answer that request. Try asking it another way."
        case .emptyResponse:
            "The on-device model returned no answer. Try again."
        case .failed:
            "Ask could not finish on this iPad. Try again."
        }
    }
}

enum AskAction: Hashable, Sendable {
    case explain
    case simplify
    case custom(String)

    static func customRequest(_ text: String) -> AskAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return .custom(String(trimmed.prefix(300)))
    }

    var request: String {
        switch self {
        case .explain:
            "Explain what the current sentence means and why it matters here."
        case .simplify:
            "Rewrite the current sentence in simpler modern English without changing its meaning."
        case let .custom(question):
            String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        }
    }
}

struct AskContext: Equatable, Sendable {
    let bookTitle: String
    let author: String
    let chapterTitle: String
    let currentSentenceID: String
    let previousSentence: String?
    let currentSentence: String
    let nextSentence: String?

    init?(document: ReaderDocument, position: ReaderPosition) {
        guard let index = document.sentences.firstIndex(where: { $0.id == position.sentenceID }) else {
            return nil
        }

        bookTitle = document.title
        author = document.author
        chapterTitle = document.chapter(containing: position.sentenceID)?.title
            ?? document.chapterTitle
        currentSentenceID = document.sentences[index].id
        currentSentence = document.sentences[index].text
        previousSentence = index > 0 ? document.sentences[index - 1].text : nil
        nextSentence = index + 1 < document.sentences.count ? document.sentences[index + 1].text : nil
    }

    func prompt(for action: AskAction) -> String {
        """
        Book: \(bookTitle)
        Author: \(author)
        Chapter: \(chapterTitle)

        Quoted passage:
        [Previous] \(previousSentence ?? "(none)")
        [Current] \(currentSentence)
        [Next] \(nextSentence ?? "(none)")

        Reader request: \(action.request)
        """
    }
}

protocol AssistantService: Sendable {
    func availability() -> AssistantAvailability
    func answer(action: AskAction, context: AskContext) async throws -> String
}
