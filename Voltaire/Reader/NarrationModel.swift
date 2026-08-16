import Foundation
import Observation

enum NarrationState: Equatable {
    case idle
    case speaking
    case paused
    case stopped
    case finished
}

@Observable
@MainActor
final class NarrationModel {
    let document: ReaderDocument

    private let engine: SpeechEngine
    private var currentIndex = 0
    private var pausedBetweenSentences = false

    var state: NarrationState = .idle
    var activeSentenceID: String?
    var activeRange: NSRange?
    var position: ReaderPosition
    var onPositionChange: ((ReaderPosition) -> Void)?
    var message: String?
    var availableVoices: [SpeechVoiceDescriptor] = []
    var selectedVoiceIdentifier: String?
    var selectedPace: NarrationPace

    init(document: ReaderDocument, position: ReaderPosition? = nil, engine: SpeechEngine) {
        self.document = document
        self.position = position ?? ReaderPosition(sentenceID: document.sentences.first?.id ?? "")
        self.engine = engine
        self.availableVoices = engine.availableVoices
        self.selectedVoiceIdentifier = engine.selectedVoiceIdentifier
        self.selectedPace = engine.selectedPace
        self.engine.onEvent = { [weak self] event in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
        }
    }

    var canStart: Bool {
        state == .idle || state == .stopped || state == .finished
    }

    var canChangeVoice: Bool {
        state != .speaking && state != .paused
    }

    var canChangePace: Bool {
        canChangeVoice
    }

    var canPreviewVoice: Bool {
        canChangeVoice && selectedVoice != nil
    }

    var selectedVoice: SpeechVoiceDescriptor? {
        availableVoices.first { $0.identifier == selectedVoiceIdentifier }
    }

    func refreshVoices() {
        availableVoices = engine.availableVoices
        selectedVoiceIdentifier = engine.selectedVoiceIdentifier
    }

    func selectVoice(identifier: String) {
        guard canChangeVoice,
              availableVoices.contains(where: { $0.identifier == identifier }),
              engine.stopVoicePreview(),
              engine.selectVoice(identifier: identifier) else {
            return
        }
        selectedVoiceIdentifier = identifier
        message = nil
    }

    func selectPace(_ pace: NarrationPace) {
        guard canChangePace,
              engine.stopVoicePreview(),
              engine.selectPace(pace) else {
            return
        }
        selectedPace = pace
        message = nil
    }

    func previewSelectedVoice() {
        guard canPreviewVoice,
              let selectedVoiceIdentifier else {
            return
        }
        message = engine.previewVoice(identifier: selectedVoiceIdentifier)
            ? nil
            : "Voice preview could not play. Try another voice."
    }

    @discardableResult
    func stopVoicePreview() -> Bool {
        engine.stopVoicePreview()
    }

    func start() {
        guard canStart, let startIndex = document.sentences.firstIndex(where: { $0.id == position.sentenceID }) else {
            return
        }

        guard engine.stopVoicePreview() else {
            message = "Voice preview could not stop. Try again."
            return
        }

        currentIndex = startIndex
        pausedBetweenSentences = false
        activeSentenceID = nil
        activeRange = nil
        message = nil
        let previousState = state
        state = .speaking
        guard speakCurrentSentence() else {
            state = previousState
            refreshVoices()
            if availableVoices.isEmpty {
                message = Self.voiceSetupMessage
            } else {
                message = "Narration could not start. Try again."
            }
            return
        }
    }

    func pause() {
        guard state == .speaking else { return }
        guard engine.pause() else {
            message = "Narration could not be paused. Try again."
            return
        }
        message = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        if pausedBetweenSentences {
            pausedBetweenSentences = false
            state = .speaking
            guard speakCurrentSentence() else {
                state = .stopped
                message = "Narration stopped before the next sentence. Try again."
                return
            }
            message = nil
            return
        }
        guard engine.resume() else {
            message = "Narration could not be resumed. Try again."
            return
        }
        message = nil
        state = .speaking
    }

    func stop() {
        guard state == .speaking || state == .paused else { return }
        if pausedBetweenSentences {
            pausedBetweenSentences = false
            message = nil
            activeSentenceID = nil
            activeRange = nil
            state = .stopped
            return
        }
        guard engine.stop() else {
            message = "Narration could not be stopped. Try again."
            return
        }
        message = nil
        activeRange = nil
        pausedBetweenSentences = false
        state = .stopped
    }

    func updatePosition(_ newPosition: ReaderPosition) {
        position = newPosition
        onPositionChange?(newPosition)
        guard state == .idle || state == .stopped || state == .finished else { return }
        activeSentenceID = nil
        activeRange = nil
    }

    private func handle(_ event: SpeechEvent) {
        switch event {
        case let .spokeRange(sentenceID, range):
            guard state == .speaking,
                  let sentence = document.sentences[safe: currentIndex],
                  sentence.id == sentenceID,
                  range.location >= 0,
                  range.length >= 0,
                  NSMaxRange(range) <= sentence.text.utf16.count else {
                return
            }

            let rowOffset = position.sentenceID == sentenceID ? position.rowOffset : 0
            position = ReaderPosition(sentenceID: sentenceID, rowOffset: rowOffset)
            onPositionChange?(position)
            activeSentenceID = sentenceID
            activeRange = range

        case let .finished(sentenceID):
            guard state == .speaking || state == .paused,
                  let sentence = document.sentences[safe: currentIndex],
                  sentence.id == sentenceID else {
                return
            }
            let wasPaused = state == .paused

            let rowOffset = position.sentenceID == sentenceID ? position.rowOffset : 0
            position = ReaderPosition(sentenceID: sentenceID, rowOffset: rowOffset)
            onPositionChange?(position)
            activeSentenceID = nil
            activeRange = nil

            if currentIndex == document.sentences.count - 1 {
                pausedBetweenSentences = false
                state = .finished
                return
            }

            currentIndex += 1
            if wasPaused {
                pausedBetweenSentences = true
                return
            }
            guard speakCurrentSentence() else {
                state = .stopped
                message = "Narration stopped before the next sentence. Try again."
                return
            }

        case let .cancelled(sentenceID):
            // A stop is intentionally non-destructive. The last valid callback
            // remains the shared reading position.
            guard state == .speaking || state == .paused,
                  document.sentences[safe: currentIndex]?.id == sentenceID else {
                return
            }
            activeRange = nil
            pausedBetweenSentences = false
            state = .stopped
        }
    }

    private func speakCurrentSentence() -> Bool {
        guard let sentence = document.sentences[safe: currentIndex] else { return false }
        return engine.speak([
            SpeechUtterance(sentenceID: sentence.id, text: sentence.text)
        ])
    }

    static let voiceSetupMessage = "In Settings, open Accessibility, then Read & Speak (Spoken Content on older iPadOS), then Voices, then English. Download a Premium or Enhanced voice and try again."
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
