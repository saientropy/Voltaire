# Voltaire handoff

This is the practical handoff for the next developer or AI working on Voltaire.

## What is here

- A native SwiftUI iPad app in `Voltaire/`.
- The Xcode project at `Voltaire.xcodeproj`.
- A 134-test Swift Testing suite in `VoltaireTests/`.
- A bundled legal public-domain Candide Chapter I sample.
- A verified public-domain EPUB fixture with provenance in `VoltaireTests/Fixtures/README.md`.
- A local simulator verification script at `scripts/automator-verify.sh`.

The app has no third-party packages, server, account system, OAuth, analytics, microphone capture, or cloud TTS.

## Start here

1. Read `DESIGN.md`, `docs/PRD.md`, `docs/APP-MAP.md`, and `docs/MILESTONES.md`.
2. Open `Voltaire.xcodeproj` in Xcode.
3. Select the `Voltaire` scheme and an iPad simulator.
4. Run the complete tests before changing behavior.

The last verified local environment was Xcode 26.6 with Swift 6.3.3 and the iOS 26.5 simulator runtime. The app deployment target is iPadOS 18.

```sh
xcodebuild -project Voltaire.xcodeproj -showdestinations
xcodebuild -project Voltaire.xcodeproj -scheme Voltaire \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -derivedDataPath /tmp/VoltaireDerived \
  CODE_SIGNING_ALLOWED=NO test
```

The local Automator app on Sai's Mac calls `scripts/automator-verify.sh`. The script finds the repository from its own location. It defaults to Sai's verified simulator identifier; set `VOLTAIRE_SIMULATOR_ID` when using another simulator.

## Verified product behavior

As of 2026-08-16:

- 134/134 simulator tests passed, with no failures or skips.
- Fresh DRM-free EPUB and clean-text PDF import passed on a physical iPad, including cold relaunch and reopen.
- Premium/Enhanced-only narration selection, preview isolation, persisted pace, live phrase highlighting, pause/resume/stop, saved reading progress, and portrait/landscape behavior passed automated physical checks.
- Ask correctly handled Apple Intelligence being disabled on the physical iPad.
- Generated results, screenshots, audio, signed apps, and device diagnostics remain locally under ignored `artifacts/`; they are not part of public Git history.

The source, tests, and Xcode project used for that final verification had the handoff fingerprint:

```text
920f2daf4039c826af2860309bdb51328e28a90fd87e4c600f4f99d7f8e71bd7
```

## Open acceptance gate

Narration quality is still a human decision. The app never falls back to Apple's Default robotic voice, but Sai has not explicitly accepted any installed Premium voice as natural enough. Voice and pace can be chosen and previewed in the Reading sheet. Do not call M1.5 complete until Sai accepts what he hears on the physical iPad.

## Known limits

- Ask is text-only. It requires iPadOS 26, compatible hardware, and Apple Intelligence enabled and model-ready for a real answer.
- EPUB support is bounded to DRM-free text, metadata, and Contents. Images, SVG, and MathML are not rendered.
- PDF support is for clean text PDFs. Scans, OCR, complex layouts, and text-to-page coordinate mapping are not supported.
- Bookmarks, annotations, book deletion, and complete failed-import recovery are not implemented.
- Imported long books are currently decoded and laid out eagerly; this needs performance work before claiming arbitrary-book scale.
- There is no TestFlight or App Store release.

## Physical-device rules

- Select the developer's own signing team in Xcode; signing identities and provisioning files are not committed.
- Install a Premium or Enhanced English Apple voice in iPad Settings before narration. Default-only voice sets are intentionally refused.
- Never reinstall an old local signed candidate after source changes. Build, test, sign, install, and verify a fresh candidate.
- Do not commit imported books, generated narration, user data, credentials, signing material, or device diagnostics.

## Safe next work

The best next step is to let Sai compare the installed Premium voices and pace settings. If all Apple voices still sound robotic, stop tuning rate or pitch: AVSpeechSynthesizer has reached its quality ceiling, and any new local or cloud narration provider needs a separate product decision.

After the narration decision, address library removal/recovery and long-book loading before adding broader features.
