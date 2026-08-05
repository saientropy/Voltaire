# Voltaire design language

## Product feeling

Voltaire should feel like reading a beautiful physical book that happens to understand what the reader needs. It must not feel like opening a PDF, operating a dashboard, or chatting with an AI product.

The hierarchy is:

1. Book text.
2. Reading position and comprehension.
3. Voice companion when intentionally summoned.
4. Everything else.

## Reading canvas

- Use a warm cream reading surface by default; exact color remains TBD.
- Use near-black warm text rather than pure black.
- The default font must be a high-quality book serif; the exact font remains TBD.
- Give text generous margins and line spacing appropriate to sustained reading.
- Do not place text inside cards.
- Do not mimic a PDF page viewer.
- Do not show permanent toolbars, chat panes, promotional content, or decorative AI gradients.
- A single deliberate tap may reveal controls; they fade away after the action.

## Adjustable reading window

The reader can control how many lines are visible at once. This is a core reading mode, not an accessibility afterthought.

- Offer useful presets initially, including a full-page view.
- Preserve book-quality typography at every setting.
- When fewer lines are visible, the remaining space stays calm rather than filling with controls.
- Changing font, size, width, spacing, or orientation must recalculate the visible reading window without losing the current sentence.
- The exact interaction and preset values require visual testing on Sai's iPad before they are finalized.

## Voice companion

- Default invocation is press-and-hold to speak.
- The companion is visually small and quiet.
- It may answer aloud, execute a reader command, or apply a reversible Language Lens.
- A spoken answer should be concise by default.
- The answer disappears and returns focus to the book.
- A transcript is available on demand for accessibility, but no persistent chat history occupies the reading screen.
- Listening, processing, success, failure, and interrupted states must be visibly distinct without becoming theatrical.

## Language Lens

The Language Lens temporarily adapts the current sentence or paragraph when requested. Examples include simplifying syntax, modernizing archaic language, translating, explaining a reference, or making an argument explicit.

- Never silently change the original.
- Label adapted text clearly but unobtrusively.
- Provide one-action access to the original.
- Preserve the reader's location when switching between original and adapted text.
- Store transformations separately from canonical book content.
- Do not adapt an entire book automatically in the first release.

## Narrated reading

- Reading and listening share one canonical position.
- Highlight the phrase being spoken without producing a karaoke-like visual effect.
- Moving between silent reading and narration resumes at the same sentence.
- Clearly distinguish narration of original text from narration of adapted text.
- Audio controls appear only while needed.

## Library

- The library is quiet, personal, and utilitarian.
- Covers, title, author, and progress are enough for the first version.
- Import is the dominant library action.
- Avoid storefront patterns, recommendations, popularity signals, and social proof.

## Motion and sound

- Motion communicates location or state; it is never decoration.
- Respect Reduce Motion.
- Page transitions should feel calm and immediate.
- Companion sounds are subtle and optional.

## Form factors

- iPad portrait and landscape are required.
- Split View and Stage Manager behavior should be considered after the core layouts are stable.
- The initial product is not required to support iPhone, Android, web, or macOS as primary reading surfaces.

## Visual review rule

No visible milestone is approved from source code alone. Provide rendered iPad screenshots for portrait, landscape, standard reading, controls revealed, companion listening, companion response, Language Lens, loading, empty, and error states relevant to that milestone.
