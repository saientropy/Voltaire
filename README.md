# Voltaire

Voltaire is a native, iPad-first reading environment for personally imported books. It is designed to feel like a beautifully typeset book, with narration and contextual text assistance available only when requested.

## Current status

The current local-first reader candidate includes a polished library and reader, bounded DRM-free EPUB and clean text PDF import, unchanged original-file storage, real EPUB Contents navigation, persistent books and reading positions, persistent text-size, line-spacing, and margin controls, exact 3–20-line and full-page reading modes, selectable Apple Premium/Enhanced English narration, a safe voice preview, saved Relaxed, Natural, and Brisk pace choices, synchronized phrase highlighting, and a small contextual Ask sheet powered by Apple's on-device model when available. It has no account, OAuth flow, backend, cloud sync, external AI key, microphone capture, analytics, or third-party package.

The complete iPad simulator suite passed 134/134 with 0 failed and 0 skipped on 2026-08-16. Local physical-iPad checks also passed fresh EPUB and PDF import, relaunch/reopen persistence, synchronized phrase movement, pause/resume/stop, saved progress, and portrait/landscape behavior. The tested iPad had Apple Intelligence turned off, so the Ask sheet's actionable unavailable state was verified rather than a live answer. Subjective narration naturalness remains an open human acceptance gate; the earlier robotic Default-voice build is rejected.

Generated test results, screenshots, audio, signing products, and device diagnostics are intentionally excluded from this public repository. They remain on Sai's development Mac under the ignored `artifacts/` directory.

## Open and run

Requirements: macOS with Xcode 26.6 or a compatible newer Xcode, an iPad simulator, and iPadOS 18 or later. Real on-device Ask responses additionally require a compatible iPad running iPadOS 26 with Apple Intelligence enabled and ready.

1. Clone the repository and open `Voltaire.xcodeproj` in Xcode.
2. Select the `Voltaire` scheme and an iPad simulator.
3. Build and run. No package download, account, backend, or API key is required.

To list destinations and run the tests from Terminal:

```sh
xcodebuild -project Voltaire.xcodeproj -showdestinations
xcodebuild -project Voltaire.xcodeproj -scheme Voltaire \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -derivedDataPath /tmp/VoltaireDerived \
  CODE_SIGNING_ALLOWED=NO test
```

On a physical iPad, select your own Apple Development team in Xcode. Install at least one English Premium or Enhanced Apple voice in iPad Settings before starting narration; Voltaire intentionally refuses a robotic Default-only fallback.

## Product foundations

- [Product requirements](docs/PRD.md)
- [Design language](DESIGN.md)
- [Visual product map](docs/APP-MAP.md)
- [Milestone gates](docs/MILESTONES.md)
- [Repository and agent guidance](AGENTS.md)
- [Technical and product handoff](HANDOFF.md)

## Core principles

- The book remains the dominant surface.
- Imported originals remain unchanged.
- Reading, listening, and assistance share one canonical reading position.
- A reversible Language Lens is a future milestone; it is not implemented in this candidate.
- AI appears only after an explicit request and immediately returns focus to reading.
- Every meaningful interface iteration is reviewed in iPad portrait and landscape and, when relevant, on a physical iPad.

## Repository status

This repository contains the native SwiftUI application, tests, legal public-domain sample and fixture, and the simulator verification script used by Sai's local Automator workflow. Physical verification evidence and signed builds are deliberately local-only; this is not an App Store or TestFlight release.

No open-source license has been selected yet.
