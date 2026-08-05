# Voltaire milestone gates

Only one milestone may be active at a time. Factory must show the proposed plan and explicit exclusions before implementation. Sai approves the result before the next milestone begins.

## M0 — Foundation

- Approve PRD, design rules, app map, and build sequence.
- Confirm first iPad target and Apple signing situation.
- Factory produces a read-only technical plan.

Exit evidence: planning response only; no app code.

## M1 — Native reader shell

- Scaffold the smallest native SwiftUI iPad app.
- Use one bundled public-domain sample chapter.
- Implement library-to-reader navigation.
- Implement cream reading canvas and temporary typography tokens.
- Implement visible-line presets and full-page mode.
- Preserve the current sentence through appearance changes and rotation.
- Add nonfunctional, clearly labeled preview states for narration, companion, and Language Lens.

Excluded: file import, persistence beyond simple sample state, real AI, microphone, generated audio, PDF/EPUB parsing, accounts, backend, TestFlight.

Exit evidence: tests, portrait/landscape screenshots, and a physical-iPad run.

## M2 — EPUB import and canonical positions

- Import one bounded class of DRM-free EPUB.
- Extract structure, text, images, and metadata.
- Store the original unchanged.
- Establish stable canonical text positions.
- Render through the approved reader rather than a web/PDF viewer.

Exit evidence: import success/failure samples, position stability tests, physical-iPad reading.

## M3 — Local persistence

- Persist library, current sentence, appearance preferences, bookmarks, and recoverable processing state locally.
- Verify relaunch, rotation, update, and failed-import recovery.

## M4 — Narration and highlighting

- Approve narration source/provider first.
- Generate or import segmented audio.
- Synchronize phrase highlighting.
- Preserve position through reading/listening transitions, seeks, speed changes, interruptions, and relaunch.

Exit evidence: physical-iPad audio, battery, interruption, and synchronization testing.

## M5 — Voice companion

- Approve transcription and response providers first.
- Add press-and-hold interaction.
- Support concise contextual questions and reader commands.
- Provide on-demand transcripts and robust failure states.

## M6 — Language Lens

- Add sentence/paragraph simplify, modernize, translate, explain, and unpack actions.
- Keep transformations explicit, separate, reversible, and position-stable.
- Test meaning preservation and failure recovery.

## M7 — Text-based PDF

- Support a bounded class of clean text-based PDFs.
- Extract canonical reading order and map text back to PDF coordinates.
- Report unsupported layouts honestly.

Excluded until later: scanned books, arbitrary OCR, perfect complex tables/equations, every multi-column layout.

## M8 — Stable beta distribution

- Confirm paid Apple Developer Program status.
- Establish signing, archive, and TestFlight process.
- Upload only after explicit authorization.
- Document rollback and feedback handling.
