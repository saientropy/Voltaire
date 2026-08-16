# Voltaire repository guide

## What this project is

Voltaire is a native, iPad-first reading app for imported books. It should feel like a beautifully typeset book with intelligence available only when requested. The canonical product requirements are in `docs/PRD.md`; permanent experience rules are in `DESIGN.md`.

## Current phase

- The current approved objective is a coherent local-first reader candidate: polished library and reader, DRM-free EPUB and clean text PDF import, real EPUB Contents navigation, local persistence, persistent reader appearance controls for text size, line spacing, and margins, Premium/Enhanced Apple narration with saved Relaxed, Natural, and Brisk pace choices, synchronized phrase highlighting, and a bounded on-device Ask sheet.
- The complete iPad (A16) simulator suite passed 134/134 with 0 failed and 0 skipped on 2026-08-16. Generated results and visual evidence are retained locally under ignored `artifacts/`, not in public Git history.
- Local physical-iPad runs passed fresh EPUB/PDF import and reopen, Premium narration selection, moving phrase highlighting, stable pause, resume/stop, progress relaunch, portrait/landscape, and the Apple Intelligence-off Ask fallback. Subjective voice naturalness remains Sai's acceptance decision. See `HANDOFF.md` for the bounded current status.
- Do not implement more than one approved milestone at a time.
- Before editing, read `DESIGN.md`, `docs/PRD.md`, `docs/APP-MAP.md`, and `docs/MILESTONES.md`.
- When Factory is in Spec Mode, inspect and plan only. Do not edit until Sai explicitly approves the plan.

## Stack decisions

- Native iPadOS application.
- Swift and SwiftUI.
- Local-first book storage, preferences, and progress. Bookmarks and annotations are not implemented yet.
- Originals remain immutable; derived assets and user state are separate.
- The contextual assistant uses Apple's on-device Foundation Models when available. Narration remains local through Apple speech voices. Do not add a cloud provider without approval.

## Commands

The native SwiftUI reader shell exists. Verified local commands:

```sh
xcodebuild -project Voltaire.xcodeproj -list
xcodebuild -project Voltaire.xcodeproj -scheme Voltaire -sdk iphonesimulator -configuration Debug -destination 'platform=iOS Simulator,id=D27D8620-F123-4944-945F-09B002DD088C' -derivedDataPath /tmp/VoltaireDerived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Voltaire.xcodeproj -scheme Voltaire -sdk iphonesimulator -configuration Debug -destination 'platform=iOS Simulator,id=D27D8620-F123-4944-945F-09B002DD088C' -derivedDataPath /tmp/VoltaireDerived CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Voltaire.xcodeproj -scheme Voltaire -sdk iphoneos -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/VoltaireDeviceDerived CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build
swiftc -typecheck -module-name Voltaire $(find Voltaire -name '*.swift' -print | sort)
```

Verified status: the saved local Automator workflow reported `SIMULATOR VERIFIED` with 134 passed, 0 failed, and 0 skipped. Local physical checks passed fresh EPUB/PDF import and persistence plus narration phrase/pause/resume/stop/rotation behavior. The physical iPad proved Ask's Apple Intelligence-off fallback, not a real model answer. Detailed binary and device evidence is deliberately ignored by Git.

The earlier robotic Default-voice build and all older signed candidates are rejected and must never be installed. Any new source revision requires a fresh build and verification before physical installation. Do not claim active Premium/Enhanced simulator audio.

## Product guardrails

- The reading canvas is always the dominant surface.
- Do not create a persistent chatbot, feed, social layer, streak system, subscription flow, or recommendation dashboard.
- AI appears only after an explicit request and then gets out of the way.
- A Language Lens transformation never overwrites the original text.
- EPUB/PDF originals must remain recoverable and unchanged.
- Build the simplest local architecture that satisfies the approved milestone.
- Do not add a backend, account system, analytics SDK, or third-party dependency without explaining why it is necessary and obtaining approval.
- Do not silently expand support from clean EPUB/text PDFs to scanned or structurally complex books.

## Design and accessibility

- Follow `DESIGN.md`; do not substitute generic AI styling.
- Support iPad portrait and landscape from the first visible milestone.
- Treat Dynamic Type, VoiceOver, Reduce Motion, contrast, comfortable touch targets, and hardware keyboard behavior as first-class requirements.
- Secondary controls should disappear during reading; one quiet theme-matched entry point may remain available on demand.

## Required workflow

1. Restate the approved milestone and exclusions.
2. Inspect the current repository and propose a file-by-file plan.
3. Wait for approval if the task began in Spec Mode.
4. Implement only the approved milestone.
5. Run focused tests and the full verified project checks.
6. Run the app in iPad portrait and landscape.
7. For reading, audio, microphone, storage, or performance behavior, verify on Sai's physical iPad when available.
8. Provide screenshots, test evidence, changed files, known limitations, and the next proposed checkpoint.

## Collaboration

- Factory and Codex must not edit the same branch simultaneously.
- Use small recoverable commits after Sai approves an iteration.
- Never push, publish, upload to TestFlight, or change Apple account/signing configuration without explicit authorization.
- Preserve user changes and unrelated work.

## Secrets and privacy

- Never commit credentials, signing material, private/imported book files, generated narration, or private annotations. The verified public-domain sample and test fixture are intentional exceptions.
- Use local ignored configuration or Apple-supported secret storage when integrations are later approved.
- Send only the minimum selected passage to a cloud AI service; never upload a full book by default.

## Definition of done

A visible feature is not done merely because it compiles. Completion requires behavior tests, portrait and landscape screenshots, accessibility review, confirmation of exclusions, and physical-iPad verification when the feature depends on real device behavior.
