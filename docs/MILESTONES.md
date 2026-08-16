# Voltaire milestone gates

Only one milestone may be active at a time. Factory must show the proposed plan and explicit exclusions before implementation. Sai approves the result before the next milestone begins.

Current override: Sai explicitly requested a coherent full local-first app rather than waiting on the original sequential gates. The implemented candidate therefore includes bounded M2, M3, M5-text, and M7 work together. The evidence below remains honest about simulator verification versus physical-iPad acceptance.

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
- Implement exact direct visible-line control from 3 through 20 lines plus Full Page.
- Preserve the current sentence through appearance changes and rotation.
- The initial M1 shell excluded narration, voice-companion, and Language-Lens preview UI. Narration is now covered by the approved M1.5 candidate below; voice companion and Language Lens remain future milestones.

Excluded: file import, persistence beyond simple sample state, real AI, microphone, generated audio, PDF/EPUB parsing, accounts, backend, TestFlight.

Exit evidence: simulator tests and current-build portrait/landscape visual checks passed. Contents, pace, appearance, Light/Dark, large-text, finite-window, touch, keyboard-command, and accessibility checks were captured locally. Generated visual and device evidence is intentionally retained outside public Git history.

## M1.5 — Apple-native narration candidate

- Preserve one canonical reading position across silent reading and narration.
- Prefer an Apple Premium English voice, fall back to Apple Enhanced English, refuse Default-only English voices, and offer saved Relaxed, Natural, and Brisk pace choices.
- Preserve stable UTF-16 phrase mapping and restrained underline highlighting.
- The earlier robotic Default-voice build is rejected and must never be installed.

Verified evidence: the complete iPad simulator suite passed 134/134 with 0 failed and 0 skipped on 2026-08-16, including voice-quality selection, Premium-to-Enhanced fallback, Default-voice refusal, preview isolation, saved pace selection, exact pace-rate mapping, callback ordering, phrase mapping, stale-callback rejection, pause/resume/stop, position preservation, appearance reflow, exhaustive 3–20-line continuity, finite-window source-anchor persistence, EPUB navigation parsing, legacy-package safety, canonical chapter jumps, PDF filename fallback/repair, and Ask accessibility-state mapping. Local physical narration checks passed Premium-voice selection, moving phrase highlighting, stable pause, resume/stop, persistent progress, and portrait/landscape. Signing products and device evidence are intentionally not committed.

Completion gate: automated physical behavior is verified. M1.5 remains incomplete until Sai accepts the selected Premium voice's naturalness by listening.

## M2 — EPUB import and canonical positions

- Import one bounded class of DRM-free EPUB.
- Extract structure, text, images, and metadata.
- Store the original unchanged.
- Establish stable canonical text positions.
- Render through the approved reader rather than a web/PDF viewer.

Exit evidence: import success/failure samples, position stability tests, physical-iPad reading.

Candidate status: partially implemented for bounded, DRM-free EPUB archives. Tests cover stored/deflated content, unsafe paths, encryption/rights rejection, duplicate entries, size limits, persistence, duplicate import, EPUB3 navigation, EPUB2 NCX fallback, fragment-to-stable-sentence mapping, fail-soft optional structure, and the verified Project Gutenberg *Candide* fixture with 71 source Contents entries. The current binary physically imported, preserved, relaunched, and reopened a separate public-domain EPUB. Text, metadata, and Contents are supported; EPUB images, SVG, and MathML are not rendered.

## M3 — Local persistence

- Persist library, current sentence, appearance preferences, bookmarks, and recoverable processing state locally.
- Verify relaunch, rotation, update, and failed-import recovery.

Candidate status: books, originals, reading position, current EPUB section, line-window preference, reader appearance (text size, line spacing, and margins), and narration voice and pace choices persist locally. Tests cover absent/corrupt appearance and chapter fallback, relaunch restoration, canonical reading/narration position preservation, all appearance reflows, active-phrase visibility, finite overflow position, rotation remapping, and safe in-place enrichment of older EPUB/PDF packages. Full-page progress and freshly imported PDF/EPUB packages survived cold relaunch and reopen. Bookmarks, annotations, book deletion, and complete failed-import recovery are not yet implemented.

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

Candidate status: a deliberately smaller text-only Ask sheet is implemented with Explain, Simplify, and a short custom question using Apple's on-device Foundation Models when available. The current test suite covers model availability, bounded context, cancellation, stale responses, and position preservation. On the physical iPad, Apple Intelligence was off; the current binary correctly showed its actionable unavailable state and kept all text local. The exact current physical candidate has not produced a real model answer. It needs no OAuth. Microphone input, spoken answers, commands, and persistent chat history remain excluded.

## M6 — Language Lens

- Add sentence/paragraph simplify, modernize, translate, explain, and unpack actions.
- Keep transformations explicit, separate, reversible, and position-stable.
- Test meaning preservation and failure recovery.

## M7 — Text-based PDF

- Support a bounded class of clean text-based PDFs.
- Extract canonical reading order and map text back to PDF coordinates.
- Report unsupported layouts honestly.

Excluded until later: scanned books, arbitrary OCR, perfect complex tables/equations, every multi-column layout.

Candidate status: partially implemented for bounded clean text-based PDFs with PDFKit, metadata/filename title extraction, stable sentences, local original storage, legacy-title repair, and clear locked/copy-protected/image-only rejection. The current suite passes coordinator-to-repository import/reload/open tests. The current physical candidate freshly imported a public-domain PDF through Files, preserved its original byte-for-byte, opened it, cold-relaunched, retained it, and reopened it. Text-to-page coordinate mapping is not implemented; scanned and complex-layout PDFs remain unsupported.

## M8 — Stable beta distribution

- Confirm paid Apple Developer Program status.
- Establish signing, archive, and TestFlight process.
- Upload only after explicit authorization.
- Document rollback and feedback handling.
