# Voltaire

Voltaire is a native, iPad-first reading environment for personally imported books. It is designed to feel like a beautifully typeset book, with narration and voice-first assistance available only when requested.

## Current status

Voltaire is in its product-foundation phase. The native application has not been scaffolded yet. Factory has produced a read-only specification for the first reader-shell milestone, which is awaiting review before implementation.

## Product foundations

- [Product requirements](docs/PRD.md)
- [Design language](DESIGN.md)
- [Visual product map](docs/APP-MAP.md)
- [Milestone gates](docs/MILESTONES.md)
- [Repository and agent guidance](AGENTS.md)

## Core principles

- The book remains the dominant surface.
- Imported originals remain unchanged.
- Reading, listening, and assistance share one canonical reading position.
- Difficult text may be adapted temporarily through a reversible Language Lens.
- AI appears only after an explicit request and immediately returns focus to reading.
- Every meaningful interface iteration is reviewed in iPad portrait and landscape and, when relevant, on a physical iPad.

## Repository status

The initial implementation target is a small native SwiftUI iPad reader shell. EPUB/PDF import, narration, voice interaction, and Language Lens behavior are separate gated milestones rather than one oversized first build.

No open-source license has been selected yet.
