# Voltaire repository guide

## What this project is

Voltaire is a native, iPad-first reading app for imported books. It should feel like a beautifully typeset book with intelligence available only when requested. The canonical product requirements are in `docs/PRD.md`; permanent experience rules are in `DESIGN.md`.

## Current phase

- Foundation and planning only.
- No application has been scaffolded yet.
- Do not implement more than one approved milestone at a time.
- Before editing, read `DESIGN.md`, `docs/PRD.md`, `docs/APP-MAP.md`, and `docs/MILESTONES.md`.
- When Factory is in Spec Mode, inspect and plan only. Do not edit until Sai explicitly approves the plan.

## Stack decisions

- Native iPadOS application.
- Swift and SwiftUI.
- Local-first book storage, preferences, progress, and annotations.
- Originals remain immutable; derived assets and user state are separate.
- Cloud AI and narration providers are TBD. Do not choose or integrate one without approval.

## Commands

There are no verified install, build, test, lint, or run commands yet. After the Xcode project is scaffolded, replace this paragraph with exact commands that have been run successfully. Never invent a command or document one as verified without running it.

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
- Controls should disappear during reading and remain discoverable on demand.

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

- Never commit credentials, signing material, book files, generated narration, or private annotations.
- Use local ignored configuration or Apple-supported secret storage when integrations are later approved.
- Send only the minimum selected passage to a cloud AI service; never upload a full book by default.

## Definition of done

A visible feature is not done merely because it compiles. Completion requires behavior tests, portrait and landscape screenshots, accessibility review, confirmation of exclusions, and physical-iPad verification when the feature depends on real device behavior.
