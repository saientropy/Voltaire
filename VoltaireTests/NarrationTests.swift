import AVFoundation
import Foundation
import Testing
@testable import Voltaire

@MainActor
struct NarrationTests {
    @Test func avSpeechEngineUsesSystemManagedAudioSession() {
        let engine = AVSpeechEngine()

        #expect(engine.usesApplicationAudioSession == false)
    }

    @Test func bookUtteranceUsesAppleNaturalCadenceWithoutChangingSourceText() {
        let source = "“Caf\u{00E9}”—Candide met Zo\u{00EB} \u{1F642}."

        let utterance = AVSpeechEngine.makeBookUtterance(text: source)

        #expect(utterance.speechString == source)
        #expect(utterance.speechString.utf16.count == source.utf16.count)
        #expect(utterance.rate == AVSpeechUtteranceDefaultSpeechRate)
        #expect(utterance.pitchMultiplier == 1)
        #expect(utterance.volume == 1)
        #expect(utterance.preUtteranceDelay == 0)
        #expect(utterance.postUtteranceDelay == 0)
        #expect(utterance.prefersAssistiveTechnologySettings == false)
    }

    @Test func narrationPacesUseModestClampedRatesWithoutChangingSourceText() {
        let source = "“Caf\u{00E9}”—Candide met Zo\u{00EB} \u{1F642}."

        for pace in NarrationPace.allCases {
            let utterance = AVSpeechEngine.makeBookUtterance(
                text: source,
                pace: pace
            )
            let expectedRate = min(
                max(
                    AVSpeechUtteranceDefaultSpeechRate * pace.rateMultiplier,
                    AVSpeechUtteranceMinimumSpeechRate
                ),
                AVSpeechUtteranceMaximumSpeechRate
            )

            #expect(utterance.speechString == source)
            #expect(utterance.speechString.utf16.count == source.utf16.count)
            #expect(utterance.rate == expectedRate)
            #expect(utterance.pitchMultiplier == 1)
            #expect(utterance.preUtteranceDelay == 0)
            #expect(utterance.postUtteranceDelay == 0)
        }
    }

    @Test func narrationPaceLabelsAndMultipliersStayIntentional() {
        #expect(NarrationPace.allCases.map(\.label) == ["Relaxed", "Natural", "Brisk"])
        #expect(NarrationPace.relaxed.rateMultiplier == 0.90)
        #expect(NarrationPace.natural.rateMultiplier == 1.00)
        #expect(NarrationPace.brisk.rateMultiplier == 1.10)
    }

    @Test func voiceLabelsRemoveOnlyTheMatchingQualitySuffix() {
        let premium = SpeechVoiceDescriptor(
            identifier: "ava",
            name: "Ava (Premium)",
            language: "en-US",
            quality: .premium
        )
        let unrelated = SpeechVoiceDescriptor(
            identifier: "reader",
            name: "Reader (Premium)",
            language: "en-IN",
            quality: .enhanced
        )

        #expect(premium.displayName == "Ava")
        #expect(premium.menuLabel == "Ava · US English")
        #expect(unrelated.displayName == "Reader (Premium)")
        #expect(unrelated.menuLabel == "Reader (Premium) · Indian English")
    }

    @Test func adapterMapsAppleVoiceQualitiesExplicitly() {
        #expect(AVSpeechEngine.mapVoiceQuality(.default) == .default)
        #expect(AVSpeechEngine.mapVoiceQuality(.enhanced) == .enhanced)
        #expect(AVSpeechEngine.mapVoiceQuality(.premium) == .premium)
    }

    @Test func voiceSelectorPrefersPremiumEnglishVoice() {
        let selected = SpeechVoiceSelector.selectEnglishVoice(from: [
            SpeechVoiceDescriptor(identifier: "en-enhanced", language: "en-US", quality: .enhanced),
            SpeechVoiceDescriptor(identifier: "en-default", language: "en-US", quality: .default),
            SpeechVoiceDescriptor(identifier: "en-premium", language: "en-US", quality: .premium)
        ])

        #expect(selected?.identifier == "en-premium")
    }

    @Test func voiceSelectorFallsBackToEnhancedEnglishVoice() {
        let selected = SpeechVoiceSelector.selectEnglishVoice(from: [
            SpeechVoiceDescriptor(identifier: "en-default", language: "en-US", quality: .default),
            SpeechVoiceDescriptor(identifier: "en-enhanced", language: "en-GB", quality: .enhanced)
        ])

        #expect(selected?.identifier == "en-enhanced")
    }

    @Test func voiceSelectorRefusesDefaultOnlyVoices() {
        let selected = SpeechVoiceSelector.selectEnglishVoice(from: [
            SpeechVoiceDescriptor(identifier: "en-default", language: "en-US", quality: .default),
            SpeechVoiceDescriptor(identifier: "fr-premium", language: "fr-FR", quality: .premium)
        ])

        #expect(selected == nil)
    }

    @Test func voiceSelectorHonorsAnInstalledPreferredPremiumVoice() {
        let selected = SpeechVoiceSelector.selectEnglishVoice(
            from: [
                SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium),
                SpeechVoiceDescriptor(identifier: "serena", name: "Serena", language: "en-GB", quality: .premium)
            ],
            preferredIdentifier: "serena"
        )

        #expect(selected?.identifier == "serena")
    }

    @Test func voiceSelectorIgnoresAnIneligiblePreferredVoice() {
        let selected = SpeechVoiceSelector.selectEnglishVoice(
            from: [
                SpeechVoiceDescriptor(identifier: "robot", language: "en-US", quality: .default),
                SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
            ],
            preferredIdentifier: "robot"
        )

        #expect(selected?.identifier == "ava")
    }

    @Test func narrationVoiceChoiceIsAppliedAndCannotChangeMidSpeech() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium),
            SpeechVoiceDescriptor(identifier: "serena", name: "Serena", language: "en-GB", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        let model = NarrationModel(document: SampleChapter.document, engine: engine)

        model.selectVoice(identifier: "serena")
        #expect(model.selectedVoiceIdentifier == "serena")
        #expect(engine.chosenVoiceIdentifier == "serena")

        model.start()
        model.selectVoice(identifier: "ava")
        #expect(model.selectedVoiceIdentifier == "serena")
        #expect(engine.chosenVoiceIdentifier == "serena")
    }

    @Test func selectedNarrationVoicePersistsAcrossSpeechEngineInstances() throws {
        let suiteName = "VoltaireTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let voices = [
            SpeechVoiceDescriptor(
                identifier: "ava",
                name: "Ava",
                language: "en-US",
                quality: .premium
            ),
            SpeechVoiceDescriptor(
                identifier: "serena",
                name: "Serena",
                language: "en-GB",
                quality: .premium
            )
        ]
        let first = AVSpeechEngine(
            defaults: defaults,
            voiceDescriptorsProvider: { voices }
        )

        #expect(first.selectVoice(identifier: "serena"))

        let reopened = AVSpeechEngine(
            defaults: defaults,
            voiceDescriptorsProvider: { voices }
        )
        #expect(reopened.selectedVoiceIdentifier == "serena")
    }

    @Test func selectedNarrationPaceDefaultsSafelyAndPersistsAcrossSpeechEngineInstances() throws {
        let suiteName = "VoltaireTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("damaged", forKey: "narration.selectedPace")

        let first = AVSpeechEngine(defaults: defaults)
        #expect(first.selectedPace == .natural)
        #expect(defaults.string(forKey: "narration.selectedPace") == NarrationPace.natural.rawValue)
        #expect(first.selectPace(.relaxed))

        let reopened = AVSpeechEngine(defaults: defaults)
        #expect(reopened.selectedPace == .relaxed)
        #expect(
            reopened.makeSelectedBookUtterance(text: "Preview and narration share this pace.").rate
                == AVSpeechUtteranceDefaultSpeechRate * NarrationPace.relaxed.rateMultiplier
        )
    }

    @Test func narrationPaceSelectionStopsPreviewAndPreservesReadingState() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        let initialPosition = ReaderPosition(sentenceID: "candide-007", rowOffset: 1)
        let model = NarrationModel(
            document: SampleChapter.document,
            position: initialPosition,
            engine: engine
        )

        model.selectPace(.relaxed)

        #expect(model.selectedPace == .relaxed)
        #expect(engine.chosenPace == .relaxed)
        #expect(engine.operationLog.suffix(2) == ["stopPreview", "selectPace"])
        #expect(model.position == initialPosition)
        #expect(model.state == .idle)
        #expect(model.activeSentenceID == nil)
        #expect(model.activeRange == nil)
    }

    @Test func narrationPaceCannotChangeWhileSpeakingOrPaused() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        engine.chosenPace = .natural
        let model = NarrationModel(document: SampleChapter.document, engine: engine)

        model.start()
        model.selectPace(.brisk)
        #expect(model.selectedPace == .natural)
        #expect(engine.chosenPace == .natural)

        model.pause()
        model.selectPace(.relaxed)
        #expect(model.selectedPace == .natural)
        #expect(engine.chosenPace == .natural)
    }

    @Test func refreshedVoiceCatalogIncludesNewlyInstalledEligibleVoices() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        let model = NarrationModel(document: SampleChapter.document, engine: engine)

        engine.voiceDescriptors.append(
            SpeechVoiceDescriptor(identifier: "serena", name: "Serena", language: "en-GB", quality: .premium)
        )
        model.refreshVoices()

        #expect(model.availableVoices.map(\.identifier) == ["ava", "serena"])
    }

    @Test func voicePreviewUsesSelectedVoiceWithoutMovingReadingOrNarrationState() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "serena", name: "Serena", language: "en-GB", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "serena"
        let initialPosition = ReaderPosition(sentenceID: "candide-007", rowOffset: 1)
        let model = NarrationModel(
            document: SampleChapter.document,
            position: initialPosition,
            engine: engine
        )
        var positionChangeCount = 0
        model.onPositionChange = { _ in positionChangeCount += 1 }

        model.previewSelectedVoice()

        #expect(engine.previewedVoiceIdentifiers == ["serena"])
        #expect(model.position == initialPosition)
        #expect(model.state == .idle)
        #expect(model.activeSentenceID == nil)
        #expect(model.activeRange == nil)
        #expect(positionChangeCount == 0)
    }

    @Test func voicePreviewIsUnavailableWhileNarrationIsActive() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        let model = NarrationModel(document: SampleChapter.document, engine: engine)

        model.start()
        model.previewSelectedVoice()

        #expect(engine.previewedVoiceIdentifiers.isEmpty)
        #expect(model.state == .speaking)
    }

    @Test func voicePreviewIsUnavailableWhileNarrationIsPaused() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        let model = NarrationModel(document: SampleChapter.document, engine: engine)

        model.start()
        model.pause()
        model.previewSelectedVoice()

        #expect(engine.previewedVoiceIdentifiers.isEmpty)
        #expect(model.state == .paused)
    }

    @Test func narrationStopsPreviewBeforeSpeaking() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        let model = NarrationModel(document: SampleChapter.document, engine: engine)

        model.start()

        #expect(engine.operationLog.prefix(2) == ["stopPreview", "speak"])
        #expect(model.state == .speaking)
    }

    @Test func failedPreviewStopRefusesNarrationWithoutMovingPosition() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        engine.stopVoicePreviewResult = false
        let initialPosition = ReaderPosition(sentenceID: "candide-007", rowOffset: 1)
        let model = NarrationModel(
            document: SampleChapter.document,
            position: initialPosition,
            engine: engine
        )

        model.start()

        #expect(model.state == .idle)
        #expect(model.position == initialPosition)
        #expect(engine.spokenBatches.isEmpty)
        #expect(model.message == "Voice preview could not stop. Try again.")
    }

    @Test func selectingAnotherVoiceStopsPreviewBeforeSelection() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium),
            SpeechVoiceDescriptor(identifier: "serena", name: "Serena", language: "en-GB", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        let model = NarrationModel(document: SampleChapter.document, engine: engine)

        model.selectVoice(identifier: "serena")

        #expect(engine.operationLog.suffix(2) == ["stopPreview", "select"])
        #expect(model.selectedVoiceIdentifier == "serena")
    }

    @Test func closingControlsAndExitingReaderStopAnIdlePreview() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        let model = ReaderModel(document: SampleChapter.document, speechEngine: engine)

        model.showControls()
        model.narration.previewSelectedVoice()
        model.cancel()
        let canExit = model.stopForExit()

        #expect(canExit == true)
        #expect(model.controlsVisible == false)
        #expect(engine.stopVoicePreviewCallCount == 2)
        #expect(model.position == ReaderPosition(sentenceID: SampleChapter.document.sentences[0].id))
    }

    @Test func missingHighQualityVoicePreservesPositionAndShowsActionableMessage() {
        let engine = FakeSpeechEngine()
        engine.speakResult = false
        let model = NarrationModel(
            document: SampleChapter.document,
            position: ReaderPosition(sentenceID: "candide-008"),
            engine: engine
        )

        model.start()

        #expect(model.state == .idle)
        #expect(model.position == ReaderPosition(sentenceID: "candide-008"))
        #expect(model.message == "In Settings, open Accessibility, then Read & Speak (Spoken Content on older iPadOS), then Voices, then English. Download a Premium or Enhanced voice and try again.")
        #expect(engine.commands == [.speak])
    }

    @Test func speechFailureWithAnEligibleVoiceShowsGenericRetryMessage() {
        let engine = FakeSpeechEngine()
        engine.voiceDescriptors = [
            SpeechVoiceDescriptor(identifier: "ava", name: "Ava", language: "en-US", quality: .premium)
        ]
        engine.chosenVoiceIdentifier = "ava"
        engine.speakResult = false
        let model = NarrationModel(document: SampleChapter.document, engine: engine)

        model.start()

        #expect(model.state == .idle)
        #expect(model.message == "Narration could not start. Try again.")
    }

    @Test func startsInIdleAndStartsFromCurrentStableSentence() {
        let engine = FakeSpeechEngine()
        let model = NarrationModel(
            document: SampleChapter.document,
            position: ReaderPosition(sentenceID: "candide-007"),
            engine: engine
        )

        model.start()

        #expect(model.state == .speaking)
        #expect(engine.commands == [.speak])
        #expect(engine.utterances.first?.sentenceID == "candide-007")
        #expect(engine.utterances.count == 1)
    }

    @Test func finishingASentenceQueuesOnlyTheNextSentence() {
        let engine = FakeSpeechEngine()
        let model = NarrationModel(
            document: SampleChapter.document,
            position: ReaderPosition(sentenceID: "candide-007"),
            engine: engine
        )
        model.start()

        engine.emit(.finished(sentenceID: "candide-007"))

        #expect(model.state == .speaking)
        #expect(engine.commands == [.speak, .speak])
        #expect(engine.utterances == [
            SpeechUtterance(
                sentenceID: "candide-008",
                text: SampleChapter.document.sentences.first { $0.id == "candide-008" }!.text
            )
        ])
    }

    @Test func staleAndDuplicateFinishesCannotSkipTheActiveSentence() {
        let engine = FakeSpeechEngine()
        let model = NarrationModel(
            document: SampleChapter.document,
            position: ReaderPosition(sentenceID: "candide-007"),
            engine: engine
        )
        model.start()

        engine.emit(.finished(sentenceID: "candide-006"))
        #expect(engine.spokenBatches.count == 1)

        engine.emit(.finished(sentenceID: "candide-007"))
        #expect(engine.spokenBatches.count == 2)
        #expect(engine.spokenBatches.last?.map(\.sentenceID) == ["candide-008"])

        engine.emit(.finished(sentenceID: "candide-007"))
        #expect(engine.spokenBatches.count == 2)
    }

    @Test func failedNextSentenceStopsAtTheLastValidPosition() {
        let engine = FakeSpeechEngine()
        let initial = ReaderPosition(sentenceID: "candide-007", rowOffset: 2)
        let model = NarrationModel(
            document: SampleChapter.document,
            position: initial,
            engine: engine
        )
        model.start()
        engine.speakResult = false

        engine.emit(.finished(sentenceID: "candide-007"))

        #expect(model.state == .stopped)
        #expect(model.position == initial)
        #expect(model.message == "Narration stopped before the next sentence. Try again.")
        #expect(engine.spokenBatches.count == 2)
        #expect(engine.spokenBatches.last?.map(\.sentenceID) == ["candide-008"])
    }

    @Test func rangeCallbackMapsToSentenceAndPreservesCanonicalPosition() {
        let engine = FakeSpeechEngine()
        let sentence = SampleChapter.document.sentences[1]
        let model = NarrationModel(
            document: SampleChapter.document,
            position: ReaderPosition(sentenceID: sentence.id),
            engine: engine
        )
        model.start()
        let range = NSRange(location: 0, length: sentence.text.utf16.count)

        engine.emit(.spokeRange(sentenceID: sentence.id, range: range))

        #expect(model.activeSentenceID == sentence.id)
        #expect(model.activeRange == range)
        #expect(model.position == ReaderPosition(sentenceID: sentence.id))
    }

    @Test func invalidRangeDoesNotCorruptPositionOrHighlight() {
        let engine = FakeSpeechEngine()
        let model = NarrationModel(document: SampleChapter.document, engine: engine)
        model.start()
        let original = model.position

        engine.emit(.spokeRange(
            sentenceID: "candide-001",
            range: NSRange(location: 0, length: 10_000)
        ))

        #expect(model.position == original)
        #expect(model.activeSentenceID == nil)
        #expect(model.activeRange == nil)
    }

    @Test func pauseResumeAndStopForwardCommandsAndPreservePosition() {
        let engine = FakeSpeechEngine()
        let model = NarrationModel(
            document: SampleChapter.document,
            position: ReaderPosition(sentenceID: "candide-004"),
            engine: engine
        )
        model.start()
        engine.emit(.spokeRange(
            sentenceID: "candide-004",
            range: NSRange(location: 0, length: 4)
        ))
        let spokenPosition = model.position

        model.pause()
        #expect(model.state == .paused)
        #expect(engine.commands == [.speak, .pause])

        model.resume()
        #expect(model.state == .speaking)
        #expect(engine.commands == [.speak, .pause, .resume])

        model.stop()
        #expect(model.state == .stopped)
        #expect(model.position == spokenPosition)
        #expect(model.activeRange == nil)
        #expect(engine.commands == [.speak, .pause, .resume, .stop])
    }

    @Test func rejectedPauseLeavesNarrationSpeaking() {
        let engine = FakeSpeechEngine()
        engine.pauseResult = false
        let model = NarrationModel(document: SampleChapter.document, engine: engine)
        model.start()

        model.pause()

        #expect(model.state == .speaking)
        #expect(model.message == "Narration could not be paused. Try again.")
    }

    @Test func rejectedResumeLeavesNarrationPaused() {
        let engine = FakeSpeechEngine()
        engine.resumeResult = false
        let model = NarrationModel(document: SampleChapter.document, engine: engine)
        model.start()
        model.pause()

        model.resume()

        #expect(model.state == .paused)
        #expect(model.message == "Narration could not be resumed. Try again.")
    }

    @Test func finishArrivingAfterPauseQueuesTheNextSentenceOnlyOnResume() {
        let engine = FakeSpeechEngine()
        let model = NarrationModel(
            document: SampleChapter.document,
            position: ReaderPosition(sentenceID: "candide-007"),
            engine: engine
        )
        model.start()
        model.pause()

        engine.emit(.finished(sentenceID: "candide-007"))

        #expect(model.state == .paused)
        #expect(engine.spokenBatches.count == 1)

        model.resume()

        #expect(model.state == .speaking)
        #expect(engine.commands == [.speak, .pause, .speak])
        #expect(engine.spokenBatches.last?.map(\.sentenceID) == ["candide-008"])
    }

    @Test func finitePagingIsDisabledWhileNarrationIsActive() {
        let engine = FakeSpeechEngine()
        let model = ReaderModel(document: SampleChapter.document, speechEngine: engine)
        model.linePreset = .lines(5)
        model.narration.start()

        #expect(model.navigationEnabled == false)

        model.narration.pause()
        #expect(model.navigationEnabled == false)

        model.narration.stop()
        #expect(model.navigationEnabled == true)
    }

    @Test func attemptedPagingLeavesPositionUnchangedWhileNarrationIsSpeakingOrPaused() {
        let engine = FakeSpeechEngine()
        let model = ReaderModel(document: SampleChapter.document, speechEngine: engine)
        model.linePreset = .lines(5)
        model.narration.start()
        let speakingPosition = model.position

        model.advance(width: 240, fontSize: 20)
        #expect(model.position == speakingPosition)

        model.narration.pause()
        let pausedPosition = model.position
        model.goBack(width: 240, fontSize: 20)
        #expect(model.position == pausedPosition)
    }

    @Test func scrollPositionUpdateCannotMoveCanonicalPositionWhileNarrationIsSpeakingOrPaused() {
        let engine = FakeSpeechEngine()
        let model = ReaderModel(document: SampleChapter.document, speechEngine: engine)
        let window = model.window(width: 240, fontSize: 20)
        let speakingPosition = model.position
        model.narration.start()

        model.updatePosition(for: window.lines.last!.id, in: window)
        #expect(model.position == speakingPosition)

        model.narration.pause()
        let pausedPosition = model.position
        model.updatePosition(for: window.lines.last!.id, in: window)
        #expect(model.position == pausedPosition)
    }

    @Test func scrollCoordinatorReanchorIsIdempotentAfterUserScroll() {
        var coordinator = ReaderScrollCoordinator()

        #expect(coordinator.prepareProgrammaticScroll(to: "line-001") == true)
        coordinator.userInteractionBegan()
        #expect(coordinator.finishUserScroll(
            finalVisibleLineID: "line-009",
            navigationEnabled: true
        ) == "line-009")
        #expect(coordinator.prepareProgrammaticScroll(to: "line-009") == false)
    }

    @Test func manualFullPageScrollCannotDesynchronizeCoordinatorWhileNarrating() {
        let engine = FakeSpeechEngine()
        let model = ReaderModel(document: SampleChapter.document, speechEngine: engine)
        let window = model.window(width: 240, fontSize: 20)
        let canonicalLineID = window.anchorLineID
        let attemptedLineID = window.lines.last!.id
        var coordinator = ReaderScrollCoordinator()
        coordinator.prepareProgrammaticScroll(to: canonicalLineID)
        coordinator.userInteractionBegan()

        model.narration.start()
        #expect(coordinator.finishUserScroll(
            finalVisibleLineID: attemptedLineID,
            navigationEnabled: model.navigationEnabled
        ) == nil)
        #expect(coordinator.canonicalLineID == canonicalLineID)

        model.narration.pause()
        coordinator.userInteractionBegan()
        #expect(coordinator.finishUserScroll(
            finalVisibleLineID: attemptedLineID,
            navigationEnabled: model.navigationEnabled
        ) == nil)
        #expect(coordinator.canonicalLineID == canonicalLineID)
    }

    @Test func rejectedStopLeavesNarrationStatePositionAndCallbacksIntact() {
        let engine = FakeSpeechEngine()
        engine.stopResult = false
        let model = NarrationModel(
            document: SampleChapter.document,
            position: ReaderPosition(sentenceID: "candide-008"),
            engine: engine
        )
        model.start()
        engine.emit(.spokeRange(
            sentenceID: "candide-008",
            range: NSRange(location: 0, length: 4)
        ))
        let position = model.position

        model.stop()
        engine.emit(.spokeRange(
            sentenceID: "candide-008",
            range: NSRange(location: 5, length: 5)
        ))

        #expect(model.state == .speaking)
        #expect(model.position == position)
        #expect(model.activeRange == NSRange(location: 5, length: 5))
        #expect(model.message == "Narration could not be stopped. Try again.")
    }

    @Test func finishingFinalSentencePreservesFinalPosition() {
        let engine = FakeSpeechEngine()
        let final = SampleChapter.document.sentences.last!
        let model = NarrationModel(
            document: SampleChapter.document,
            position: ReaderPosition(sentenceID: final.id, rowOffset: 2),
            engine: engine
        )
        model.start()

        engine.emit(.spokeRange(
            sentenceID: final.id,
            range: NSRange(location: 0, length: final.text.utf16.count)
        ))
        engine.emit(.finished(sentenceID: final.id))

        #expect(model.state == .finished)
        #expect(model.position == ReaderPosition(sentenceID: final.id, rowOffset: 2))
        #expect(model.activeSentenceID == nil)
        #expect(model.activeRange == nil)
    }

    @Test func activePhraseMovesFiniteWindowToTheSpokenLineAndPreservesItOnStop() {
        let sentence = ReaderSentence(
            id: "long-001",
            text: "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty."
        )
        let document = ReaderDocument(
            id: "long-book",
            title: "Long Book",
            author: "Test",
            chapterTitle: "One",
            sentences: [sentence]
        )
        let engine = FakeSpeechEngine()
        let model = ReaderModel(document: document, speechEngine: engine)
        model.linePreset = .lines(3)
        model.startNarration()
        let lateWordRange = (sentence.text as NSString).range(of: "nineteen")

        engine.emit(.spokeRange(sentenceID: sentence.id, range: lateWordRange))
        model.revealActivePhrase(width: 180, fontSize: 20)

        let visible = model.window(width: 180, fontSize: 20)
        #expect(model.position.rowOffset > 0)
        #expect(visible.lines.contains {
            NSIntersectionRange($0.sourceRange, lateWordRange).length > 0
        })

        let spokenPosition = model.position
        model.narration.stop()
        #expect(model.position == spokenPosition)
    }

    @Test func appearanceReflowKeepsTheActiveNarrationPhraseVisible() {
        let sentence = ReaderSentence(
            id: "appearance-narration",
            text: String(repeating: "A changing page should keep the spoken phrase visible. ", count: 12)
        )
        let document = ReaderDocument(
            id: "appearance-book",
            title: "Appearance Book",
            author: "Test",
            chapterTitle: "One",
            sentences: [sentence]
        )
        let engine = FakeSpeechEngine()
        let model = ReaderModel(document: document, speechEngine: engine)
        model.linePreset = .lines(3)
        model.startNarration()
        let activeRange = (sentence.text as NSString).range(
            of: "spoken phrase",
            options: .backwards
        )

        engine.emit(.spokeRange(sentenceID: sentence.id, range: activeRange))
        model.appearance = ReaderAppearance(
            textSize: .extraLarge,
            lineSpacing: .relaxed,
            margin: .wide
        )
        model.revealActivePhrase(width: 280, fontSize: 28)

        let visible = model.window(width: 280, fontSize: 28)
        #expect(model.narration.state == .speaking)
        #expect(model.narration.activeSentenceID == sentence.id)
        #expect(model.narration.activeRange == activeRange)
        #expect(model.position.sentenceID == sentence.id)
        #expect(model.narration.position == model.position)
        #expect(visible.lines.contains {
            NSIntersectionRange($0.sourceRange, activeRange).length > 0
        })
    }

    @Test func readerModelSharesNarrationPosition() {
        let engine = FakeSpeechEngine()
        let model = ReaderModel(
            document: SampleChapter.document,
            speechEngine: engine,
            initialPosition: ReaderPosition(sentenceID: "candide-012")
        )
        model.narration.start()

        engine.emit(.spokeRange(
            sentenceID: "candide-012",
            range: NSRange(location: 0, length: 5)
        ))

        #expect(model.position.sentenceID == "candide-012")
        #expect(model.narration.position == model.position)

        model.narration.stop()
        #expect(model.position.sentenceID == "candide-012")
    }

    @Test func successfulNarrationStartDismissesControlsAndShowsActiveBar() {
        let engine = FakeSpeechEngine()
        let model = ReaderModel(document: SampleChapter.document, speechEngine: engine)
        model.controlsVisible = true

        let started = model.startNarration()

        #expect(started == true)
        #expect(model.controlsVisible == false)
        #expect(model.showsNarrationBar == true)
    }

    @Test func failedNarrationStartKeepsControlsOpenAndHidesActiveBar() {
        let engine = FakeSpeechEngine()
        engine.speakResult = false
        let model = ReaderModel(document: SampleChapter.document, speechEngine: engine)
        model.controlsVisible = true

        let started = model.startNarration()

        #expect(started == false)
        #expect(model.controlsVisible == true)
        #expect(model.showsNarrationBar == false)
    }

    @Test func stopForExitStopsSpeechAndPreservesReadingPosition() {
        let engine = FakeSpeechEngine()
        let model = ReaderModel(
            document: SampleChapter.document,
            speechEngine: engine,
            initialPosition: ReaderPosition(sentenceID: "candide-006")
        )
        model.startNarration()
        engine.emit(.spokeRange(
            sentenceID: "candide-006",
            range: NSRange(location: 0, length: 4)
        ))
        let position = model.position

        let canExit = model.stopForExit()

        #expect(canExit == true)
        #expect(model.narration.state == .stopped)
        #expect(model.position == position)
        #expect(engine.commands == [.speak, .stop])
    }

    @Test func failedStopDoesNotClaimTheReaderCanExit() {
        let engine = FakeSpeechEngine()
        engine.stopResult = false
        let model = ReaderModel(document: SampleChapter.document, speechEngine: engine)
        model.startNarration()

        let canExit = model.stopForExit()

        #expect(canExit == false)
        #expect(model.narration.state == .speaking)
        #expect(model.showsNarrationBar == true)
    }
}

private final class FakeSpeechEngine: SpeechEngine {
    enum Command: Equatable {
        case speak
        case pause
        case resume
        case stop
    }

    var onEvent: ((SpeechEvent) -> Void)?
    var commands: [Command] = []
    var utterances: [SpeechUtterance] = []
    var spokenBatches: [[SpeechUtterance]] = []
    var speakResult = true
    var pauseResult = true
    var resumeResult = true
    var stopResult = true
    var voiceDescriptors: [SpeechVoiceDescriptor] = []
    var chosenVoiceIdentifier: String?
    var chosenPace: NarrationPace = .natural
    var previewedVoiceIdentifiers: [String] = []
    var stopVoicePreviewResult = true
    var stopVoicePreviewCallCount = 0
    var operationLog: [String] = []

    var availableVoices: [SpeechVoiceDescriptor] {
        voiceDescriptors
    }

    var selectedVoiceIdentifier: String? {
        chosenVoiceIdentifier
    }

    var selectedPace: NarrationPace {
        chosenPace
    }

    func selectVoice(identifier: String) -> Bool {
        guard voiceDescriptors.contains(where: { $0.identifier == identifier }) else {
            return false
        }
        operationLog.append("select")
        chosenVoiceIdentifier = identifier
        return true
    }

    func selectPace(_ pace: NarrationPace) -> Bool {
        operationLog.append("selectPace")
        chosenPace = pace
        return true
    }

    func previewVoice(identifier: String) -> Bool {
        guard voiceDescriptors.contains(where: { $0.identifier == identifier }) else {
            return false
        }
        previewedVoiceIdentifiers.append(identifier)
        operationLog.append("preview")
        return true
    }

    func stopVoicePreview() -> Bool {
        stopVoicePreviewCallCount += 1
        operationLog.append("stopPreview")
        return stopVoicePreviewResult
    }

    @discardableResult
    func speak(_ utterances: [SpeechUtterance]) -> Bool {
        commands.append(.speak)
        operationLog.append("speak")
        self.utterances = utterances
        spokenBatches.append(utterances)
        return speakResult
    }

    func pause() -> Bool {
        commands.append(.pause)
        return pauseResult
    }

    func resume() -> Bool {
        commands.append(.resume)
        return resumeResult
    }

    func stop() -> Bool {
        commands.append(.stop)
        return stopResult
    }

    func emit(_ event: SpeechEvent) {
        onEvent?(event)
    }
}
