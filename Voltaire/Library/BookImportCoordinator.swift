import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

enum BookImportError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedFile
    case fileAccessFailed
    case duplicateBook
    case invalidPDF
    case lockedPDF
    case copyProtectedPDF
    case scannedPDF
    case invalidEPUB
    case protectedEPUB
    case unsupportedArchive
    case unsafeArchive
    case bookTooLarge
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "Choose a DRM-free EPUB or a text-based PDF."
        case .fileAccessFailed:
            "Voltaire could not open that file. Try choosing it again."
        case .duplicateBook:
            "That book is already in your library."
        case .invalidPDF:
            "That PDF could not be read."
        case .lockedPDF:
            "That PDF is locked. Unlock it before importing."
        case .copyProtectedPDF:
            "That PDF does not allow text extraction."
        case .scannedPDF:
            "That PDF contains scanned pages, not selectable text. OCR is not supported yet."
        case .invalidEPUB:
            "That EPUB is damaged or incomplete."
        case .protectedEPUB:
            "That EPUB is encrypted or DRM-protected. Voltaire imports DRM-free books only."
        case .unsupportedArchive:
            "That EPUB uses an archive format Voltaire does not support."
        case .unsafeArchive:
            "That EPUB contains unsafe file paths and was not imported."
        case .bookTooLarge:
            "That book is too large to import safely."
        case .noReadableText:
            "No readable book text was found in that file."
        }
    }
}

actor BookImportCoordinator {
    private static let maximumSourceBytes = 250 * 1024 * 1024
    private let repository: LibraryRepository
    private let fileManager: FileManager

    init(
        repository: LibraryRepository,
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.fileManager = fileManager
    }

    func importBook(from sourceURL: URL) async throws -> ReaderDocument {
        let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "Voltaire-Import-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let fileExtension = sourceURL.pathExtension.lowercased()
        guard fileExtension == "pdf" || fileExtension == "epub" else {
            throw BookImportError.unsupportedFile
        }
        let copiedURL = temporaryDirectory.appendingPathComponent("source.\(fileExtension)")
        do {
            try coordinatedCopy(from: sourceURL, to: copiedURL)
        } catch let error as BookImportError {
            throw error
        } catch {
            throw BookImportError.fileAccessFailed
        }

        let bookID = try sha256Hex(of: copiedURL)
        guard !(await repository.containsBook(id: bookID)) else {
            throw BookImportError.duplicateBook
        }

        let document: ReaderDocument
        switch fileExtension {
        case "pdf":
            document = try PDFBookParser.parse(
                url: copiedURL,
                bookID: bookID,
                fallbackTitle: sourceURL.deletingPathExtension().lastPathComponent
            )
        case "epub":
            document = try EPUBBookParser.parse(url: copiedURL, bookID: bookID)
        default:
            throw BookImportError.unsupportedFile
        }

        do {
            try await repository.install(
                document: document,
                originalFileURL: copiedURL,
                originalFilename: sourceURL.lastPathComponent
            )
        } catch LibraryRepositoryError.duplicateBook {
            throw BookImportError.duplicateBook
        } catch LibraryRepositoryError.emptyBook {
            throw BookImportError.noReadableText
        } catch {
            throw error
        }
        return document
    }

    private func coordinatedCopy(from sourceURL: URL, to destinationURL: URL) throws {
        let started = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if started {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try boundedCopy(from: coordinatedURL, to: destinationURL)
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw BookImportError.fileAccessFailed
        }
        try result.get()
    }

    private func boundedCopy(from sourceURL: URL, to destinationURL: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        let reportedSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard reportedSize <= Self.maximumSourceBytes else {
            throw BookImportError.bookTooLarge
        }
        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw BookImportError.fileAccessFailed
        }

        do {
            let source = try FileHandle(forReadingFrom: sourceURL)
            defer { try? source.close() }
            let destination = try FileHandle(forWritingTo: destinationURL)
            defer { try? destination.close() }

            var copiedBytes = 0
            while let chunk = try source.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                copiedBytes += chunk.count
                guard copiedBytes <= Self.maximumSourceBytes else {
                    throw BookImportError.bookTooLarge
                }
                try destination.write(contentsOf: chunk)
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    private func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum BookTextProcessor {
    struct SentenceResult: Equatable, Sendable {
        let sentences: [ReaderSentence]
        let firstSentenceIDsByBlock: [String?]
    }

    static func makeSentences(
        blocks: [String],
        bookID: String,
        startingAt startingIndex: Int = 0
    ) -> [ReaderSentence] {
        processSentences(
            blocks: blocks,
            bookID: bookID,
            startingAt: startingIndex
        ).sentences
    }

    static func processSentences(
        blocks: [String],
        bookID: String,
        startingAt startingIndex: Int = 0
    ) -> SentenceResult {
        let prefix = String(bookID.prefix(12))
        var sentences: [ReaderSentence] = []
        var firstSentenceIDsByBlock: [String?] = []
        firstSentenceIDsByBlock.reserveCapacity(blocks.count)

        for block in blocks {
            let normalized = normalize(block)
            guard !normalized.isEmpty else {
                firstSentenceIDsByBlock.append(nil)
                continue
            }

            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = normalized
            var sentenceTexts: [String] = []
            tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
                let sentence = normalize(String(normalized[range]))
                if !sentence.isEmpty {
                    sentenceTexts.append(sentence)
                }
                return true
            }
            if sentenceTexts.isEmpty {
                sentenceTexts.append(normalized)
            }

            let blockStartIndex = sentences.count
            sentences.append(contentsOf: sentenceTexts.enumerated().map { index, text in
                ReaderSentence(
                    id: "\(prefix)-\(String(format: "%06d", startingIndex + blockStartIndex + index + 1))",
                    text: text
                )
            })
            firstSentenceIDsByBlock.append(sentences[blockStartIndex].id)
        }

        return SentenceResult(
            sentences: sentences,
            firstSentenceIDsByBlock: firstSentenceIDsByBlock
        )
    }

    static func normalize(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PDFBookParser {
    static func parse(
        url: URL,
        bookID: String,
        fallbackTitle: String? = nil
    ) throws -> ReaderDocument {
        guard let pdf = PDFDocument(url: url) else {
            throw BookImportError.invalidPDF
        }
        guard !pdf.isLocked else {
            throw BookImportError.lockedPDF
        }
        guard pdf.allowsCopying else {
            throw BookImportError.copyProtectedPDF
        }
        guard pdf.pageCount > 0, pdf.pageCount <= 10_000 else {
            throw BookImportError.invalidPDF
        }

        var pages: [String] = []
        var totalCharacters = 0
        for pageIndex in 0..<pdf.pageCount {
            guard let pageText = pdf.page(at: pageIndex)?.string else { continue }
            let normalized = BookTextProcessor.normalize(pageText)
            guard !normalized.isEmpty else { continue }
            totalCharacters += normalized.count
            guard totalCharacters <= 20_000_000 else {
                throw BookImportError.bookTooLarge
            }
            pages.append(normalized)
        }
        guard !pages.isEmpty else {
            throw BookImportError.scannedPDF
        }

        let sentences = BookTextProcessor.makeSentences(blocks: pages, bookID: bookID)
        guard !sentences.isEmpty else {
            throw BookImportError.noReadableText
        }

        let attributes = pdf.documentAttributes
        let title = cleanMetadata(
            attributes?[PDFDocumentAttribute.titleAttribute] as? String,
            fallback: cleanMetadata(
                fallbackTitle,
                fallback: url.deletingPathExtension().lastPathComponent
            )
        )
        let author = cleanMetadata(
            attributes?[PDFDocumentAttribute.authorAttribute] as? String,
            fallback: "Unknown author"
        )
        let chapter = ReaderChapter(
            id: "\(String(bookID.prefix(12)))-section-0001",
            title: "Full text",
            startSentenceID: sentences[0].id
        )
        return ReaderDocument(
            id: bookID,
            title: title,
            author: author,
            chapterTitle: "Full text",
            sentences: sentences,
            chapters: [chapter]
        )
    }

    private static func cleanMetadata(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        let normalized = BookTextProcessor.normalize(value)
        return normalized.isEmpty ? fallback : normalized
    }
}
