import Foundation

struct SpeechUtterance: Equatable {
    let sentenceID: String
    let text: String
}

enum NarrationPace: String, CaseIterable, Identifiable, Sendable {
    case relaxed
    case natural
    case brisk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relaxed:
            "Relaxed"
        case .natural:
            "Natural"
        case .brisk:
            "Brisk"
        }
    }

    var rateMultiplier: Float {
        switch self {
        case .relaxed:
            0.90
        case .natural:
            1.00
        case .brisk:
            1.10
        }
    }
}

enum SpeechVoiceQuality: Int, Equatable {
    case `default`
    case enhanced
    case premium
}

struct SpeechVoiceDescriptor: Equatable {
    let identifier: String
    let name: String
    let language: String
    let quality: SpeechVoiceQuality

    init(
        identifier: String,
        name: String? = nil,
        language: String,
        quality: SpeechVoiceQuality
    ) {
        self.identifier = identifier
        self.name = name ?? identifier
        self.language = language
        self.quality = quality
    }

    var qualityLabel: String {
        switch quality {
        case .default:
            "Default"
        case .enhanced:
            "Enhanced"
        case .premium:
            "Premium"
        }
    }

    var displayName: String {
        let qualitySuffix = " (\(qualityLabel))"
        guard name.count > qualitySuffix.count,
              name.lowercased().hasSuffix(qualitySuffix.lowercased()) else {
            return name
        }
        return String(name.dropLast(qualitySuffix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var languageLabel: String {
        switch language.lowercased() {
        case "en": "English"
        case "en-us": "US English"
        case "en-gb": "British English"
        case "en-au": "Australian English"
        case "en-in": "Indian English"
        case "en-ca": "Canadian English"
        case "en-ie": "Irish English"
        case "en-nz": "New Zealand English"
        case "en-sg": "Singapore English"
        case "en-za": "South African English"
        default:
            language
        }
    }

    var menuLabel: String {
        "\(displayName) · \(languageLabel)"
    }
}

enum SpeechVoiceSelector {
    static func eligibleEnglishVoices(from voices: [SpeechVoiceDescriptor]) -> [SpeechVoiceDescriptor] {
        voices
            .filter { $0.language.lowercased() == "en" || $0.language.lowercased().hasPrefix("en-") }
            .filter { $0.quality == .premium || $0.quality == .enhanced }
            .sorted {
                if $0.quality != $1.quality {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                let firstUS = $0.language.lowercased() == "en-us"
                let secondUS = $1.language.lowercased() == "en-us"
                if firstUS != secondUS {
                    return firstUS
                }
                if $0.language != $1.language {
                    return $0.language < $1.language
                }
                if $0.name != $1.name {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.identifier < $1.identifier
            }
    }

    static func selectEnglishVoice(
        from voices: [SpeechVoiceDescriptor],
        preferredIdentifier: String? = nil
    ) -> SpeechVoiceDescriptor? {
        let eligibleVoices = eligibleEnglishVoices(from: voices)
        if let preferredIdentifier,
           let preferred = eligibleVoices.first(where: { $0.identifier == preferredIdentifier }) {
            return preferred
        }
        return eligibleVoices.first
    }
}

enum SpeechEvent {
    case spokeRange(sentenceID: String, range: NSRange)
    case finished(sentenceID: String)
    case cancelled(sentenceID: String)
}

protocol SpeechEngine: AnyObject {
    var onEvent: ((SpeechEvent) -> Void)? { get set }
    var availableVoices: [SpeechVoiceDescriptor] { get }
    var selectedVoiceIdentifier: String? { get }
    var selectedPace: NarrationPace { get }

    @discardableResult
    func speak(_ utterances: [SpeechUtterance]) -> Bool
    @discardableResult
    func selectVoice(identifier: String) -> Bool
    @discardableResult
    func selectPace(_ pace: NarrationPace) -> Bool
    @discardableResult
    func previewVoice(identifier: String) -> Bool
    @discardableResult
    func stopVoicePreview() -> Bool
    func pause() -> Bool
    func resume() -> Bool
    func stop() -> Bool
}

extension SpeechEngine {
    var availableVoices: [SpeechVoiceDescriptor] { [] }
    var selectedVoiceIdentifier: String? { nil }
    var selectedPace: NarrationPace { .natural }

    @discardableResult
    func selectVoice(identifier: String) -> Bool { false }

    @discardableResult
    func selectPace(_ pace: NarrationPace) -> Bool { false }

    @discardableResult
    func previewVoice(identifier: String) -> Bool { false }

    @discardableResult
    func stopVoicePreview() -> Bool { true }
}
