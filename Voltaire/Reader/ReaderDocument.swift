struct ReaderDocument: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let title: String
    let author: String
    let chapterTitle: String
    let sentences: [ReaderSentence]
    let chapters: [ReaderChapter]

    init(
        id: String,
        title: String,
        author: String,
        chapterTitle: String,
        sentences: [ReaderSentence],
        chapters: [ReaderChapter] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.chapterTitle = chapterTitle
        self.sentences = sentences
        self.chapters = chapters
    }

    var navigationChapters: [ReaderChapter] {
        let sentenceIndices = Dictionary(
            uniqueKeysWithValues: sentences.enumerated().map { ($0.element.id, $0.offset) }
        )
        var seenIDs: Set<String> = []
        var seenStarts: Set<String> = []
        var lastSentenceIndex = -1
        let valid = chapters.compactMap { chapter -> ReaderChapter? in
            let normalizedTitle = chapter.title
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !chapter.id.isEmpty,
                  !normalizedTitle.isEmpty,
                  let sentenceIndex = sentenceIndices[chapter.startSentenceID],
                  sentenceIndex > lastSentenceIndex,
                  !seenIDs.contains(chapter.id),
                  !seenStarts.contains(chapter.startSentenceID) else {
                return nil
            }
            seenIDs.insert(chapter.id)
            seenStarts.insert(chapter.startSentenceID)
            lastSentenceIndex = sentenceIndex
            return ReaderChapter(
                id: chapter.id,
                title: normalizedTitle,
                level: min(max(chapter.level, 0), 3),
                startSentenceID: chapter.startSentenceID
            )
        }
        if let first = valid.first,
           sentenceIndices[first.startSentenceID] != 0,
           let firstSentence = sentences.first {
            return [ReaderChapter(
                id: "\(id)-start",
                title: "Start",
                startSentenceID: firstSentence.id
            )] + valid
        }
        if !valid.isEmpty {
            return valid
        }
        guard let firstSentence = sentences.first else { return [] }
        let normalizedFallback = chapterTitle
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return [ReaderChapter(
            id: "\(id)-full-text",
            title: normalizedFallback.isEmpty ? "Full text" : normalizedFallback,
            startSentenceID: firstSentence.id
        )]
    }

    func chapter(containing sentenceID: String) -> ReaderChapter? {
        let sentenceIndices = Dictionary(
            uniqueKeysWithValues: sentences.enumerated().map { ($0.element.id, $0.offset) }
        )
        guard let sentenceIndex = sentenceIndices[sentenceID] else {
            return navigationChapters.first
        }
        var current: ReaderChapter?
        for chapter in navigationChapters {
            guard let chapterIndex = sentenceIndices[chapter.startSentenceID] else {
                continue
            }
            if chapterIndex > sentenceIndex {
                break
            }
            current = chapter
        }
        return current
    }

    var libraryStructureLabel: String {
        let rawChapterIDs = Set(chapters.map(\.id))
        let validatedRawChapters = navigationChapters.filter {
            rawChapterIDs.contains($0.id)
        }
        let displayedChapters = validatedRawChapters.isEmpty
            ? navigationChapters
            : validatedRawChapters
        return displayedChapters.count > 1
            ? "\(displayedChapters.count) sections"
            : displayedChapters.first?.title ?? chapterTitle
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case chapterTitle
        case sentences
        case chapters
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        chapterTitle = try container.decode(String.self, forKey: .chapterTitle)
        sentences = try container.decode([ReaderSentence].self, forKey: .sentences)
        chapters = (try? container.decode([ReaderChapter].self, forKey: .chapters)) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(chapterTitle, forKey: .chapterTitle)
        try container.encode(sentences, forKey: .sentences)
        try container.encode(chapters, forKey: .chapters)
    }
}

struct ReaderSentence: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let text: String
}

struct ReaderChapter: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let title: String
    let level: Int
    let startSentenceID: String

    init(
        id: String,
        title: String,
        level: Int = 0,
        startSentenceID: String
    ) {
        self.id = id
        self.title = title
        self.level = level
        self.startSentenceID = startSentenceID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case level
        case startSentenceID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 0
        startSentenceID = try container.decode(String.self, forKey: .startSentenceID)
    }
}
