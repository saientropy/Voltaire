# Voltaire visual product map

This map describes product surfaces, not a final visual design. Rendered iPad mockups must be approved separately before M1 implementation.

```mermaid
flowchart TD
    L["Quiet personal library"] --> I["Import book"]
    I --> P["Processing and compatibility state"]
    P -->|Ready| R["Reading canvas"]
    P -->|Problem| E["Clear recoverable error"]
    L --> R

    R --> C["Controls revealed temporarily"]
    C --> T["Typography and visible lines"]
    C --> N["Narration controls"]
    C --> B["Bookmark and appearance"]

    R --> V["Press and hold voice companion"]
    V --> Q{"Intent"}
    Q --> A["Brief spoken answer"]
    Q --> X["Reader command"]
    Q --> G["Language Lens"]
    A --> R
    X --> R
    G --> O["Adapted passage with original one action away"]
    O --> R

    R --> S["Session ends at canonical sentence"]
    S --> L
```

## What is normally visible

- The book text.
- A very small reading-position indicator if enabled.
- A quiet companion affordance if enabled.

## What appears only on request

- Reader controls.
- Typography and line-count settings.
- Narration controls.
- Spoken-answer transcript.
- Adapted Language Lens passage.
- Original/adapted comparison.
- Book information and processing detail.

## What does not exist in the personal MVP

- Home feed.
- Storefront.
- Social activity.
- Reading streak dashboard.
- Permanent AI chat screen.
- Subscription or account surface.
- Public profile.
