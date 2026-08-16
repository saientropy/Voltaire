# Voltaire Product Requirements Document

Status: Foundation draft for Factory planning

Product: Voltaire

Primary surface: Native iPad app

Last updated: 2026-08-05

## 1. Product statement

Voltaire is a focused reading environment for personally imported books. It transforms EPUB and PDF sources into a book-quality, synchronized reading experience with optional narration and a small voice-first AI companion. The intelligence exists to preserve momentum and comprehension; it must never compete with the book for attention.

## 2. Problem

Opening a PDF is not the same as reading a well-designed book. Conventional readers also treat text, audiobook playback, explanations, and notes as separate experiences. When a passage is difficult, the reader is pushed into a browser or chatbot and often does not return. These interruptions make difficult books easier to abandon.

## 3. Product promise

The reader can open a book, see exactly as much text as feels comfortable, move seamlessly between reading and listening, ask a brief spoken question, temporarily adapt a difficult passage, and return immediately to the same reading position.

## 4. Goals

- Make sustained reading feel calm, tactile, and book-like on iPad.
- Help Sai finish more books without relying on distracting external tools.
- Synchronize visual text, narration, and reading position.
- Provide voice-first help that minimizes interruption.
- Preserve the original book while allowing reversible derived experiences.
- Keep the first architecture small, local-first, and extensible.
- Make every meaningful iteration inspectable on Sai's physical iPad.

## 5. Non-goals

- A PDF viewer with AI controls attached.
- A general chatbot or research workspace.
- A bookstore, recommendation feed, social network, or reading competition.
- Automatic full-book rewriting.
- DRM removal or circumvention.
- Perfect support for every document format in the first release.
- Accounts, subscriptions, teams, or public sharing in the personal MVP.
- Autonomous App Store or TestFlight publishing.

## 6. Primary user

The initial user is Sai, reading on an iPad and managing development from Macs with Codex, Factory, Xcode, and Git. The architecture may later support other readers, but multi-user infrastructure must not distort the personal MVP.

## 7. Core workflows

### 7.1 Import and library

1. Import a supported DRM-free EPUB or text-based PDF through the Files picker or Share Sheet.
2. Preserve the untouched original.
3. Process the source into Voltaire's internal book package.
4. Show processing state, errors, and supported limitations honestly.
5. Add the book to a quiet library with cover, title, author, progress, and last-read position.

### 7.2 Read

1. Open a book at the saved sentence.
2. Display book-quality reflowed text on a cream surface.
3. Allow control of font, size, spacing, margins, theme, and visible line count.
4. Hide controls during sustained reading.
5. Preserve location through rotation, setting changes, relaunch, and mode changes.

### 7.3 Listen and follow

1. Begin narration from the current sentence.
2. Highlight the currently spoken phrase.
3. Choose a saved Relaxed, Natural, or Brisk pace before narration, and pause, resume, or stop without covering the page.
4. Stop listening and continue reading at the same sentence.
5. Resume audio after silent reading from the updated sentence.

### 7.4 Ask the companion

1. Press and hold the companion control.
2. Ask a question or give a reader command naturally.
3. Show a restrained listening/processing state.
4. Answer briefly through speech, perform the command, or offer a Language Lens action.
5. Return focus to the text immediately.
6. Make a transcript available only when requested or required for accessibility.

### 7.5 Use the Language Lens

1. Ask by voice or select the current sentence/paragraph.
2. Choose or infer an explicit transformation: simplify, modernize, translate, explain, or unpack.
3. Replace only the visible rendering with clearly labeled adapted text.
4. Keep the original available in one action.
5. Preserve the canonical position and annotations.
6. Optionally read the adapted passage aloud while clearly labeling it as adapted.

### 7.6 Resume after time away

1. Open the book at the exact saved position.
2. Optionally show a short, dismissible re-entry reminder.
3. Continue reading without opening a dashboard or chat history.

## 8. Functional requirements

### Reader

- Reflow text rather than display a raw PDF surface whenever extraction quality permits.
- Provide a full-page mode and adjustable visible-line modes.
- Maintain a stable canonical sentence identifier across reflow and appearance changes.
- Support bookmarks and highlights after core reading stability is proven.
- Support portrait and landscape from the first visible milestone.

### Book package

Each imported book has logically separate layers:

- Immutable original source.
- Canonical extracted text and structural hierarchy.
- Mapping from canonical text back to EPUB locations or PDF page coordinates.
- Images, footnotes, tables, and metadata.
- Optional narration audio and timing data.
- Optional derived AI transformations and explanations.
- Separate user state: progress, appearance, bookmarks, highlights, and preferences.

The package format must be versioned and regenerable. Regenerating derived assets must not destroy user state.

### Voice and AI

- Voice interaction is explicitly invoked; no always-listening microphone in the MVP.
- The companion receives the minimum context needed to answer.
- Cloud AI provider, transcription provider, speech synthesis provider, model, and pricing strategy remain TBD.
- The default response is concise and book-specific.
- The companion must distinguish questions, reader commands, and transformation requests.
- Failure must leave the book usable and the reading position intact.

### Offline behavior

- Imported books, reading, progress, appearance settings, and already-downloaded audio work offline.
- Cloud-dependent questions and new transformations fail clearly and non-destructively when offline.
- Offline narration generation is a later investigation, not an MVP promise.

## 9. UX requirements

- The reader understands the primary action within two seconds.
- Book text dominates the screen in every normal reading state.
- Only the quiet Back, Ask, and Reading entry buttons persist visually; all secondary controls remain dismissible and return focus to the book.
- The interface avoids generic cards, dashboards, badges, AI gradients, and noisy gamification.
- Every assistant state has a clear exit back to reading.
- Original and adapted text are never visually ambiguous.
- Rotation and appearance changes never lose the current sentence.
- Touch targets remain comfortable during prolonged reading and while holding the iPad.

## 10. Accessibility

- Support Dynamic Type without breaking the reading-position model.
- Provide VoiceOver labels and logical focus order.
- Respect Reduce Motion.
- Maintain sufficient contrast across themes.
- Do not rely on color alone to distinguish original, adapted, listening, or error states.
- Provide a readable transcript of spoken interactions on demand.
- Support external keyboards for navigation and reader controls when practical.

## 11. Platform and architecture

Confirmed:

- Native iPadOS app using Swift and SwiftUI.
- Mac-based development with Xcode.
- Local-first storage for books and reader state.
- Direct physical-iPad installation for fast iterations.
- TestFlight only for approved stable milestones.

Recommended pending implementation research:

- Begin without a backend or account system.
- Use Apple-native frameworks before third-party dependencies.
- Use deterministic local identifiers for canonical text positions.
- Isolate import/processing from reader rendering so more formats can be added later.

TBD:

- Minimum supported iPadOS version.
- Persistence implementation.
- EPUB parsing library or in-house approach.
- Narration, transcription, and AI providers.
- Whether book processing runs entirely on-device, on Mac, or through an optional service.
- Final internal book-package schema and extension.

## 12. Privacy and security

- Keep originals and annotations local by default.
- Never send an entire book to a cloud provider by default.
- Clearly identify any passage that will leave the device for an AI request.
- Store secrets outside the repository.
- Request microphone, file, and network permissions only when the relevant feature is used.
- Never alter, replace, or delete an imported original without explicit user action.

## 13. Quality and performance

- Page/line transitions should feel immediate on the target iPad.
- Reader appearance changes must not visibly jump to another location.
- Long books must not require loading the entire rendered text into one visible view.
- Audio highlighting must remain synchronized at every supported pace and after pause, resume, interruption, and relaunch.
- Import errors must identify the failing stage and preserve the original source.
- Battery, memory, and thermal behavior must be checked on a physical iPad before narration or AI milestones are approved.

## 14. Iteration and evidence

Each visible milestone must include:

- Successful build and automated test results.
- Portrait and landscape simulator screenshots.
- Relevant empty, loading, success, interrupted, offline, and failure states.
- Physical-iPad verification for reading, rotation, microphone, audio, storage, or performance changes.
- A plain-language summary of changes and exclusions.
- A recoverable Git checkpoint before the next milestone.

Factory and Codex must not edit the same branch at the same time. Factory is the default milestone implementer; Codex is the default independent reviewer and visual verifier. Either may switch roles when explicitly agreed.

## 15. Current local-first candidate acceptance criteria

The approved local-first candidate overrides the original spoken-companion and Language Lens MVP sequencing. Press-and-hold voice interaction and reversible Language Lens transformations remain M5/M6 work rather than acceptance gates for this candidate.

The personal MVP is complete when Sai can:

1. Import at least one supported DRM-free EPUB and one supported text-based PDF.
2. Read either as reflowed, book-quality text rather than a raw document viewer.
3. Adjust typography and visible line count without losing position.
4. Close and reopen Voltaire at the same sentence.
5. Start narration from that sentence and see restrained phrase highlighting.
6. Stop narration and continue reading from the same location.
7. Ask for concise contextual text help from the current passage and receive an on-device answer when Apple's model is available, or a clear actionable unavailable state otherwise.
8. Dismiss contextual help without changing the canonical reading or narration position.
9. Keep imported source files unchanged through processing and relaunch.
10. Use the core experience in portrait and landscape on the physical iPad.

## 16. Risks

- PDF structure and reading order vary dramatically; scope must remain bounded.
- Word-level audio timing can drift after speed changes or regenerated narration.
- AI transformations can distort meaning; original text must remain primary and accessible.
- Excessive assistance can become more distracting than the difficulty it solves.
- Poor text-position identifiers can break progress and annotations after reprocessing.
- Building import, narration, AI, and polished reading simultaneously would hide fundamental UX failures.

## 17. Decision register

| ID | Decision | State |
|---|---|---|
| D01 | Finish books with minimal interference | Confirmed |
| D02 | Import personal EPUB and PDF files | Confirmed |
| D03 | Native iPad app | Confirmed |
| D04 | Reading and narration share one canonical position | Confirmed |
| D05 | Preserve originals and compile derived book packages | Recommended |
| D11 | Reader controls visible line count | Confirmed |
| D12 | Book-quality typography is foundational | Confirmed |
| D13 | Assistant is voice-first | Confirmed |
| D14 | Difficult text can be transformed in real time | Confirmed |
| D15 | Transformations are explicit, reversible, and separate | Recommended |
| D16 | Warm cream default; final font and colors selected later | Confirmed |
| D17 | No persistent chat UI during reading | Confirmed |
| D18 | Swift and SwiftUI | Recommended from Apple-native constraint |
| D19 | Personal local-first MVP | Recommended |
| D20 | Cloud intelligence only when requested | Recommended |
| D21 | Press-and-hold voice activation | Recommended |
| D22 | EPUB and text-based PDF before complex/scanned PDF | Recommended |
| D23 | Product name is Voltaire | Confirmed |
| D24 | Apple-native and iPad-first | Confirmed |
| D25 | Meaningful iterations are viewable on Sai's physical iPad | Confirmed |
| D26 | Portrait and landscape visual evidence | Confirmed |
| D27 | Direct Xcode installation for the fast loop | Recommended |
| D28 | TestFlight for stable milestones | Recommended |
| D29 | Factory builds and Codex independently reviews by default | Recommended |
| D30 | Never let Factory and Codex edit the same branch simultaneously | Recommended |

## 18. Open questions

- Does Sai have an active paid Apple Developer Program membership for TestFlight?
- Which iPad model and iPadOS version are the first physical targets?
- Which first book should be bundled or imported for realistic testing?
- Which default serif font and precise cream palette feel right after physical-iPad review?
- Should adapted narration speak the transformed passage automatically or only after an explicit request?
- Which AI, transcription, and narration providers satisfy quality, latency, privacy, and cost requirements?
