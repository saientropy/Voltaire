import AVFoundation
import Foundation

final class AVSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onEvent: ((SpeechEvent) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let previewSynthesizer = AVSpeechSynthesizer()
    private let defaults: UserDefaults
    private let voiceDescriptorsProvider: () -> [SpeechVoiceDescriptor]
    private var utteranceIDs: [ObjectIdentifier: String] = [:]
    private static let selectedVoiceDefaultsKey = "narration.selectedVoiceIdentifier"
    private static let selectedPaceDefaultsKey = "narration.selectedPace"

    init(
        defaults: UserDefaults = .standard,
        voiceDescriptorsProvider: @escaping () -> [SpeechVoiceDescriptor] = {
            AVSpeechEngine.voiceDescriptors(from: AVSpeechSynthesisVoice.speechVoices())
        }
    ) {
        self.defaults = defaults
        self.voiceDescriptorsProvider = voiceDescriptorsProvider
        super.init()
        synthesizer.usesApplicationAudioSession = false
        previewSynthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }

    var usesApplicationAudioSession: Bool {
        synthesizer.usesApplicationAudioSession
    }

    var availableVoices: [SpeechVoiceDescriptor] {
        voiceDescriptorsProvider()
    }

    var selectedVoiceIdentifier: String? {
        let voices = availableVoices
        let storedIdentifier = defaults.string(forKey: Self.selectedVoiceDefaultsKey)
        let resolvedIdentifier = SpeechVoiceSelector.selectEnglishVoice(
            from: voices,
            preferredIdentifier: storedIdentifier
        )?.identifier
        if resolvedIdentifier != storedIdentifier {
            defaults.set(resolvedIdentifier, forKey: Self.selectedVoiceDefaultsKey)
        }
        return resolvedIdentifier
    }

    var selectedPace: NarrationPace {
        guard let rawValue = defaults.string(forKey: Self.selectedPaceDefaultsKey),
              let pace = NarrationPace(rawValue: rawValue) else {
            defaults.set(NarrationPace.natural.rawValue, forKey: Self.selectedPaceDefaultsKey)
            return .natural
        }
        return pace
    }

    @discardableResult
    func selectVoice(identifier: String) -> Bool {
        guard availableVoices.contains(where: { $0.identifier == identifier }) else {
            return false
        }
        guard stopVoicePreview() else { return false }
        defaults.set(identifier, forKey: Self.selectedVoiceDefaultsKey)
        return true
    }

    @discardableResult
    func selectPace(_ pace: NarrationPace) -> Bool {
        guard stopVoicePreview() else { return false }
        defaults.set(pace.rawValue, forKey: Self.selectedPaceDefaultsKey)
        return true
    }

    @discardableResult
    func previewVoice(identifier: String) -> Bool {
        guard utteranceIDs.isEmpty,
              let voice = Self.selectEnglishVoice(
                  from: AVSpeechSynthesisVoice.speechVoices(),
                  preferredIdentifier: identifier
              ),
              voice.identifier == identifier else {
            return false
        }

        guard stopVoicePreview() else { return false }
        let utterance = makeSelectedBookUtterance(
            text: "At first, everything seemed certain; then, suddenly, it did not.",
            voice: voice
        )
        previewSynthesizer.speak(utterance)
        return true
    }

    @discardableResult
    func stopVoicePreview() -> Bool {
        guard previewSynthesizer.isSpeaking || previewSynthesizer.isPaused else { return true }
        return previewSynthesizer.stopSpeaking(at: .immediate)
    }

    @discardableResult
    func speak(_ utterances: [SpeechUtterance]) -> Bool {
        guard utterances.count == 1, let item = utterances.first else {
            return false
        }
        guard let voice = Self.selectEnglishVoice(
            from: AVSpeechSynthesisVoice.speechVoices(),
            preferredIdentifier: selectedVoiceIdentifier
        ) else {
            return false
        }

        // A finished utterance is removed before NarrationModel asks us to
        // enqueue the next sentence. Only interrupt speech when a tracked
        // utterance is genuinely still active.
        guard utteranceIDs.isEmpty else { return false }

        guard stopVoicePreview() else { return false }

        let utterance = makeSelectedBookUtterance(
            text: item.text,
            voice: voice
        )
        utteranceIDs[ObjectIdentifier(utterance)] = item.sentenceID
        synthesizer.speak(utterance)
        return true
    }

    func pause() -> Bool {
        synthesizer.pauseSpeaking(at: .immediate)
    }

    func resume() -> Bool {
        synthesizer.continueSpeaking()
    }

    func stop() -> Bool {
        let stopped = synthesizer.stopSpeaking(at: .immediate)
        if stopped {
            utteranceIDs.removeAll()
        }
        return stopped
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        guard let sentenceID = utteranceIDs[ObjectIdentifier(utterance)] else { return }
        onEvent?(.spokeRange(sentenceID: sentenceID, range: characterRange))
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        guard let sentenceID = utteranceIDs.removeValue(forKey: ObjectIdentifier(utterance)) else { return }
        onEvent?(.finished(sentenceID: sentenceID))
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        guard let sentenceID = utteranceIDs.removeValue(forKey: ObjectIdentifier(utterance)) else { return }
        onEvent?(.cancelled(sentenceID: sentenceID))
    }

    static func voiceDescriptors(from voices: [AVSpeechSynthesisVoice]) -> [SpeechVoiceDescriptor] {
        let descriptors = voices.map {
            SpeechVoiceDescriptor(
                identifier: $0.identifier,
                name: $0.name,
                language: $0.language,
                quality: Self.mapVoiceQuality($0.quality)
            )
        }
        return SpeechVoiceSelector.eligibleEnglishVoices(from: descriptors)
    }

    static func selectEnglishVoice(
        from voices: [AVSpeechSynthesisVoice],
        preferredIdentifier: String? = nil
    ) -> AVSpeechSynthesisVoice? {
        guard let selected = SpeechVoiceSelector.selectEnglishVoice(
            from: voiceDescriptors(from: voices),
            preferredIdentifier: preferredIdentifier
        ) else {
            return nil
        }
        return voices.first { $0.identifier == selected.identifier }
    }

    static func mapVoiceQuality(_ quality: AVSpeechSynthesisVoiceQuality) -> SpeechVoiceQuality {
        switch quality {
        case .default:
            .default
        case .enhanced:
            .enhanced
        case .premium:
            .premium
        @unknown default:
            .default
        }
    }

    static func makeBookUtterance(
        text: String,
        voice: AVSpeechSynthesisVoice? = nil,
        pace: NarrationPace = .natural
    ) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(
            max(
                AVSpeechUtteranceDefaultSpeechRate * pace.rateMultiplier,
                AVSpeechUtteranceMinimumSpeechRate
            ),
            AVSpeechUtteranceMaximumSpeechRate
        )
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        utterance.prefersAssistiveTechnologySettings = false
        return utterance
    }

    func makeSelectedBookUtterance(
        text: String,
        voice: AVSpeechSynthesisVoice? = nil
    ) -> AVSpeechUtterance {
        Self.makeBookUtterance(
            text: text,
            voice: voice,
            pace: selectedPace
        )
    }
}
