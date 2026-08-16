import CryptoKit
import Foundation
import PDFKit

struct StoredBookPackage: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let document: ReaderDocument
    let originalFilename: String
    let importedAt: Date
}

enum LibraryRepositoryError: Error, Equatable, Sendable {
    case invalidBookID
    case emptyBook
    case duplicateBook
    case invalidPackage
}

actor LibraryRepository {
    private let rootURL: URL
    private let fileManager: FileManager

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voltaire", isDirectory: true)
            .appendingPathComponent("Books", isDirectory: true)
    }

    func loadDocuments() throws -> [ReaderDocument] {
        try ensureRootExists()
        let packageURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return packageURLs.compactMap { packageURL in
            guard (try? packageURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let data = try? Data(contentsOf: manifestURL(for: packageURL)),
                  let package = try? JSONDecoder().decode(StoredBookPackage.self, from: data),
                  package.schemaVersion == StoredBookPackage.currentSchemaVersion,
                  packageURL.lastPathComponent == package.document.id,
                  isValidImportedBookID(package.document.id),
                  isReadable(package.document) else {
                return nil
            }
            let titleRepairedPackage = packageRepairingLegacyPDFTitle(
                package,
                at: packageURL,
                manifestData: data
            )
            return packageEnrichingLegacyChapters(
                titleRepairedPackage,
                at: packageURL
            ).document
        }
        .sorted {
            let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
            return titleOrder == .orderedSame ? $0.id < $1.id : titleOrder == .orderedAscending
        }
    }

    func containsBook(id: String) -> Bool {
        guard isValidImportedBookID(id) else { return false }
        return fileManager.fileExists(atPath: packageURL(for: id).path)
    }

    func install(
        document: ReaderDocument,
        originalFileURL: URL,
        originalFilename: String
    ) throws {
        guard isValidImportedBookID(document.id) else {
            throw LibraryRepositoryError.invalidBookID
        }
        guard isReadable(document) else {
            throw LibraryRepositoryError.emptyBook
        }

        try ensureRootExists()
        let finalURL = packageURL(for: document.id)
        guard !fileManager.fileExists(atPath: finalURL.path) else {
            throw LibraryRepositoryError.duplicateBook
        }

        let stagingURL = rootURL.appendingPathComponent(
            ".incoming-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let originalsURL = stagingURL.appendingPathComponent("Original", isDirectory: true)
        try fileManager.createDirectory(at: originalsURL, withIntermediateDirectories: false)
        let sourceExtension = originalFileURL.pathExtension.lowercased()
        let storedSourceName = sourceExtension.isEmpty ? "source" : "source.\(sourceExtension)"
        try fileManager.copyItem(
            at: originalFileURL,
            to: originalsURL.appendingPathComponent(storedSourceName)
        )

        let package = StoredBookPackage(
            schemaVersion: StoredBookPackage.currentSchemaVersion,
            document: document,
            originalFilename: URL(fileURLWithPath: originalFilename).lastPathComponent,
            importedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = try encoder.encode(package)
        try manifest.write(to: manifestURL(for: stagingURL), options: .atomic)

        try fileManager.moveItem(at: stagingURL, to: finalURL)
    }

    private func ensureRootExists() throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    private func packageURL(for id: String) -> URL {
        rootURL.appendingPathComponent(id, isDirectory: true)
    }

    private func manifestURL(for packageURL: URL) -> URL {
        packageURL.appendingPathComponent("book.json", isDirectory: false)
    }

    private func packageEnrichingLegacyChapters(
        _ package: StoredBookPackage,
        at packageURL: URL
    ) -> StoredBookPackage {
        guard package.schemaVersion == StoredBookPackage.currentSchemaVersion,
              package.document.chapters.isEmpty else {
            return package
        }

        let originalURL = packageURL
            .appendingPathComponent("Original", isDirectory: true)
            .appendingPathComponent("source.epub", isDirectory: false)

        do {
            let values = try originalURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  try sha256Hex(of: originalURL) == package.document.id else {
                return package
            }

            let parsed = try EPUBBookParser.parse(
                url: originalURL,
                bookID: package.document.id
            )
            guard parsed.sentences == package.document.sentences,
                  !parsed.chapters.isEmpty else {
                return package
            }

            let rawChapterIDs = Set(parsed.chapters.map(\.id))
            let validatedChapters = parsed.navigationChapters.filter {
                rawChapterIDs.contains($0.id)
            }
            guard !validatedChapters.isEmpty else { return package }

            let document = ReaderDocument(
                id: package.document.id,
                title: package.document.title,
                author: package.document.author,
                chapterTitle: package.document.chapterTitle,
                sentences: package.document.sentences,
                chapters: validatedChapters
            )
            let updated = StoredBookPackage(
                schemaVersion: package.schemaVersion,
                document: document,
                originalFilename: package.originalFilename,
                importedAt: package.importedAt
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updated)
            try data.write(to: manifestURL(for: packageURL), options: .atomic)
            return updated
        } catch {
            return package
        }
    }

    private func packageRepairingLegacyPDFTitle(
        _ package: StoredBookPackage,
        at packageURL: URL,
        manifestData: Data
    ) -> StoredBookPackage {
        let storedTitle = BookTextProcessor.normalize(package.document.title)
        let originalFilename = URL(fileURLWithPath: package.originalFilename).lastPathComponent
        let originalURLFromName = URL(fileURLWithPath: originalFilename)
        let originalTitle = BookTextProcessor.normalize(
            originalURLFromName.deletingPathExtension().lastPathComponent
        )
        guard package.schemaVersion == StoredBookPackage.currentSchemaVersion,
              storedTitle == "source",
              originalURLFromName.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame,
              !originalTitle.isEmpty,
              originalTitle.caseInsensitiveCompare("source") != .orderedSame else {
            return package
        }

        let originalURL = packageURL
            .appendingPathComponent("Original", isDirectory: true)
            .appendingPathComponent("source.pdf", isDirectory: false)

        do {
            let values = try originalURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  try sha256Hex(of: originalURL) == package.document.id else {
                return package
            }

            guard let pdf = PDFDocument(url: originalURL),
                  !pdf.isLocked,
                  pdf.allowsCopying else {
                return package
            }
            let metadataTitle = BookTextProcessor.normalize(
                pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? ""
            )
            guard metadataTitle.isEmpty else { return package }

            let parsed = try PDFBookParser.parse(
                url: originalURL,
                bookID: package.document.id,
                fallbackTitle: originalTitle
            )
            let repairedTitle = BookTextProcessor.normalize(parsed.title)
            guard parsed.sentences == package.document.sentences,
                  !repairedTitle.isEmpty,
                  repairedTitle.caseInsensitiveCompare("source") != .orderedSame else {
                return package
            }

            let document = ReaderDocument(
                id: package.document.id,
                title: repairedTitle,
                author: package.document.author,
                chapterTitle: package.document.chapterTitle,
                sentences: package.document.sentences,
                chapters: package.document.chapters
            )
            let updated = StoredBookPackage(
                schemaVersion: package.schemaVersion,
                document: document,
                originalFilename: package.originalFilename,
                importedAt: package.importedAt
            )

            guard var root = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
                  var storedDocument = root["document"] as? [String: Any],
                  BookTextProcessor.normalize(storedDocument["title"] as? String ?? "") == "source" else {
                return package
            }
            storedDocument["title"] = repairedTitle
            root["document"] = storedDocument
            let currentManifestData = try Data(contentsOf: manifestURL(for: packageURL))
            guard currentManifestData == manifestData else { return package }
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: manifestURL(for: packageURL), options: .atomic)
            return updated
        } catch {
            return package
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

    private func isReadable(_ document: ReaderDocument) -> Bool {
        !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !document.sentences.isEmpty &&
        document.sentences.allSatisfy {
            !$0.id.isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } &&
        Set(document.sentences.map(\.id)).count == document.sentences.count
    }

    private func isValidImportedBookID(_ id: String) -> Bool {
        id.count == 64 && id.allSatisfy(\.isHexDigit)
    }
}
