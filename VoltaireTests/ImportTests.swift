import Compression
import CryptoKit
import Foundation
import PDFKit
import Testing
import UIKit
@testable import Voltaire

struct ImportTests {
    @Test func textProcessorCreatesStableSentenceIDs() {
        let bookID = String(repeating: "a", count: 64)
        let sentences = BookTextProcessor.makeSentences(
            blocks: ["First sentence. Second sentence!"],
            bookID: bookID
        )

        #expect(sentences.map(\.id) == [
            "aaaaaaaaaaaa-000001",
            "aaaaaaaaaaaa-000002"
        ])
        #expect(sentences.map(\.text) == ["First sentence.", "Second sentence!"])
    }

    @Test @MainActor func cleanTextPDFExtractsMetadataAndSentences() throws {
        let url = temporaryFileURL(extension: "pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "A Test Book",
            kCGPDFContextAuthor as String: "Ada Reader"
        ]
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
            format: format
        )
        let data = renderer.pdfData { context in
            context.beginPage()
            let text = "A first sentence. A second sentence follows."
            (text as NSString).draw(
                in: CGRect(x: 72, y: 72, width: 468, height: 200),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
            )
        }
        try data.write(to: url)

        let document = try PDFBookParser.parse(
            url: url,
            bookID: String(repeating: "b", count: 64)
        )

        #expect(document.title == "A Test Book")
        #expect(document.author == "Ada Reader")
        #expect(document.sentences.count == 2)
        #expect(document.sentences[0].text == "A first sentence.")
        #expect(document.navigationChapters.map(\.title) == ["Full text"])
        #expect(document.navigationChapters[0].startSentenceID == document.sentences[0].id)
    }

    @Test @MainActor func imageOnlyPDFIsRejectedAsScanned() throws {
        let url = temporaryFileURL(extension: "pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792)
        )
        let data = renderer.pdfData { context in
            context.beginPage()
            UIColor.black.setFill()
            context.fill(CGRect(x: 80, y: 80, width: 200, height: 120))
        }
        try data.write(to: url)

        var caught: BookImportError?
        do {
            _ = try PDFBookParser.parse(
                url: url,
                bookID: String(repeating: "c", count: 64)
            )
        } catch let error as BookImportError {
            caught = error
        }
        #expect(caught == .scannedPDF)
    }

    @Test func storedEPUBParsesMetadataSpineAndText() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeValidEPUB(chapterCompression: .stored).write(to: url)

        let document = try EPUBBookParser.parse(
            url: url,
            bookID: String(repeating: "d", count: 64)
        )

        #expect(document.title == "The Test Book")
        #expect(document.author == "Grace Author")
        #expect(document.chapterTitle == "Chapter One")
        #expect(document.sentences.map(\.text) == [
            "Chapter One",
            "The first EPUB sentence.",
            "The second EPUB sentence."
        ])
        #expect(document.navigationChapters.map(\.title) == ["Chapter One"])
        #expect(document.navigationChapters[0].startSentenceID == document.sentences[0].id)
    }

    @Test func deflatedEPUBContentDecodes() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeValidEPUB(chapterCompression: .deflated).write(to: url)

        let document = try EPUBBookParser.parse(
            url: url,
            bookID: String(repeating: "e", count: 64)
        )

        #expect(document.sentences.contains { $0.text == "The first EPUB sentence." })
    }

    @Test func realPublicDomainGutenbergEPUBImports() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Candide-Project-Gutenberg-19942.epub")
        let document = try EPUBBookParser.parse(
            url: fixture,
            bookID: "8a49864e18c9b100b067aebb01542854a9b053cae6d82b5a08aa5cc4e868f4b6"
        )

        #expect(document.title.localizedCaseInsensitiveContains("Candide"))
        #expect(document.author.localizedCaseInsensitiveContains("Voltaire"))
        #expect(document.sentences.count == 2_241)
        var sentenceHasher = SHA256()
        for sentence in document.sentences {
            sentenceHasher.update(data: Data("\(sentence.id)\n\(sentence.text)\n".utf8))
        }
        let sentenceDigest = sentenceHasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(sentenceDigest == "7ab76779f7d0175b1c46f040bf12c70214a1fc228a87d6efdf26bdbe5e315e98")
        #expect(document.chapters.count == 71)
        #expect(!document.chapters.contains { $0.title == "Start" })
        #expect(document.navigationChapters.count == 72)
        #expect(document.navigationChapters.first?.title == "Start")
        #expect(document.navigationChapters.first?.startSentenceID == document.sentences.first?.id)
        #expect(document.libraryStructureLabel == "71 sections")
        #expect(document.chapters.first { $0.title == "CANDIDE I" }?.startSentenceID == "8a49864e18c9-000085")
        #expect(document.chapters.first {
            $0.title == "HOW CANDIDE WAS BROUGHT UP IN A MAGNIFICENT CASTLE, AND HOW HE WAS EXPELLED THENCE."
        }?.startSentenceID == "8a49864e18c9-000087")
        #expect(document.chapters.first { $0.title == "II" }?.startSentenceID == "8a49864e18c9-000115")
        #expect(document.chapters.first {
            $0.title == "WHAT BECAME OF CANDIDE AMONG THE BULGARIANS."
        }?.startSentenceID == "8a49864e18c9-000116")
    }

    @Test func epub3ContentsMapsNestedAnchorsToStableSentences() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeNavigationEPUB(kind: .epub3).write(to: url)

        let document = try EPUBBookParser.parse(
            url: url,
            bookID: String(repeating: "4", count: 64)
        )

        #expect(document.chapters.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(document.chapters.map(\.level) == [0, 1])
        #expect(document.chapters.map(\.startSentenceID) == [
            "444444444444-000001",
            "444444444444-000003"
        ])
    }

    @Test func epub2NCXFallbackPreservesOrderDepthAndTargets() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeNavigationEPUB(kind: .ncx).write(to: url)

        let document = try EPUBBookParser.parse(
            url: url,
            bookID: String(repeating: "5", count: 64)
        )

        #expect(document.chapters.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(document.chapters.map(\.level) == [0, 1])
        #expect(document.chapters.map(\.startSentenceID) == [
            "555555555555-000001",
            "555555555555-000003"
        ])
    }

    @Test func brokenOptionalContentsFallsBackWithoutRejectingBook() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeNavigationEPUB(kind: .brokenEPUB3).write(to: url)

        let document = try EPUBBookParser.parse(
            url: url,
            bookID: String(repeating: "3", count: 64)
        )

        #expect(document.sentences.count == 4)
        #expect(document.navigationChapters.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(document.navigationChapters.map(\.startSentenceID) == [
            "333333333333-000001",
            "333333333333-000003"
        ])
    }

    @Test func legacyDocumentWithoutChaptersDecodesWithSafeFallback() throws {
        let data = Data("""
        {
          "id": "legacy-book",
          "title": "Legacy",
          "author": "Reader",
          "chapterTitle": "Full text",
          "sentences": [{"id": "legacy-001", "text": "Still readable."}]
        }
        """.utf8)

        let document = try JSONDecoder().decode(ReaderDocument.self, from: data)

        #expect(document.chapters.isEmpty)
        #expect(document.navigationChapters.map(\.title) == ["Full text"])
        #expect(document.navigationChapters[0].startSentenceID == "legacy-001")
    }

    @Test func malformedOptionalChaptersNeverHideAReadablePackage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let bookID = String(repeating: "a", count: 64)
        let document = ReaderDocument(
            id: bookID,
            title: "Readable Legacy Book",
            author: "Reader",
            chapterTitle: "Full text",
            sentences: [ReaderSentence(id: "legacy-001", text: "Still readable.")]
        )
        let package = StoredBookPackage(
            schemaVersion: 1,
            document: document,
            originalFilename: "Legacy.pdf",
            importedAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        var packageJSON = try #require(
            JSONSerialization.jsonObject(with: encodedPackage(package)) as? [String: Any]
        )
        var documentJSON = try #require(packageJSON["document"] as? [String: Any])
        documentJSON["chapters"] = [["id": 7, "title": false]]
        packageJSON["document"] = documentJSON
        let manifest = try JSONSerialization.data(
            withJSONObject: packageJSON,
            options: [.prettyPrinted, .sortedKeys]
        )
        let packageURL = root.appendingPathComponent(bookID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        let manifestURL = packageURL.appendingPathComponent("book.json")
        try manifest.write(to: manifestURL)
        let repository = LibraryRepository(rootURL: root)

        let loaded = try await repository.loadDocuments()

        #expect(loaded == [document])
        #expect(loaded[0].navigationChapters.map(\.title) == ["Full text"])
        #expect(try Data(contentsOf: manifestURL) == manifest)
    }

    @Test func legacyPDFWithoutChaptersStaysVisibleAndByteUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let bookID = String(repeating: "b", count: 64)
        let document = ReaderDocument(
            id: bookID,
            title: "Legacy PDF",
            author: "Reader",
            chapterTitle: "Full text",
            sentences: [ReaderSentence(id: "legacy-pdf-001", text: "A clean page.")]
        )
        let package = StoredBookPackage(
            schemaVersion: 1,
            document: document,
            originalFilename: "Legacy.pdf",
            importedAt: Date(timeIntervalSinceReferenceDate: 2)
        )
        let packageURL = root.appendingPathComponent(bookID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: packageURL.appendingPathComponent("Original", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("%PDF legacy fixture".utf8).write(
            to: packageURL.appendingPathComponent("Original/source.pdf")
        )
        let manifest = try encodedPackageWithoutChapters(package)
        let manifestURL = packageURL.appendingPathComponent("book.json")
        try manifest.write(to: manifestURL)
        let repository = LibraryRepository(rootURL: root)

        let loaded = try await repository.loadDocuments()

        #expect(loaded == [document])
        #expect(loaded[0].navigationChapters.map(\.title) == ["Full text"])
        #expect(try Data(contentsOf: manifestURL) == manifest)
    }

    @Test func documentChaptersRoundTripInSchemaOne() throws {
        let document = ReaderDocument(
            id: "round-trip",
            title: "Round Trip",
            author: "Reader",
            chapterTitle: "One",
            sentences: [
                ReaderSentence(id: "round-001", text: "One."),
                ReaderSentence(id: "round-002", text: "Two.")
            ],
            chapters: [
                ReaderChapter(id: "chapter-one", title: "One", startSentenceID: "round-001"),
                ReaderChapter(id: "chapter-two", title: "Two", level: 1, startSentenceID: "round-002")
            ]
        )

        let package = StoredBookPackage(
            schemaVersion: 1,
            document: document,
            originalFilename: "round.epub",
            importedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try JSONDecoder().decode(
            StoredBookPackage.self,
            from: JSONEncoder().encode(package)
        )

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.document == document)
    }

    @Test func commonNamedEntitiesRemainReadable() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        var builder = TestZIPBuilder()
        addValidEPUBFiles(
            to: &builder,
            chapterCompression: .stored,
            chapterXHTML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><body>
              <h1>Chapter One</h1><p>Copyright &copy; 2026. Café &eacute;lan.</p>
            </body></html>
            """
        )
        try builder.build().write(to: url)

        let document = try EPUBBookParser.parse(
            url: url,
            bookID: String(repeating: "7", count: 64)
        )

        #expect(document.sentences.contains { $0.text.contains("Copyright © 2026") })
        #expect(document.sentences.contains { $0.text.contains("Café élan") })
    }

    @Test func unreadableRequiredSpineChapterFailsTheImport() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        var builder = TestZIPBuilder()
        addValidEPUBFiles(
            to: &builder,
            chapterCompression: .stored,
            chapterXHTML: "<html><body><p>Broken &unknownEntity; chapter.</p></body></html>"
        )
        try builder.build().write(to: url)

        var caught: BookImportError?
        do {
            _ = try EPUBBookParser.parse(
                url: url,
                bookID: String(repeating: "8", count: 64)
            )
        } catch let error as BookImportError {
            caught = error
        }
        #expect(caught == .invalidEPUB)
    }

    @Test func standardFontObfuscationDoesNotLookLikeBookDRM() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        var builder = TestZIPBuilder()
        addValidEPUBFiles(to: &builder, chapterCompression: .stored)
        builder.add(
            path: "OEBPS/fonts/reader.otf",
            data: Data("obfuscated font bytes".utf8),
            compression: .stored
        )
        builder.add(
            path: "META-INF/encryption.xml",
            data: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
                        xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
              <enc:EncryptedData>
                <enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
                <enc:CipherData><enc:CipherReference URI="OEBPS/fonts/reader.otf"/></enc:CipherData>
              </enc:EncryptedData>
            </encryption>
            """.utf8),
            compression: .stored
        )
        try builder.build().write(to: url)

        let document = try EPUBBookParser.parse(
            url: url,
            bookID: String(repeating: "9", count: 64)
        )
        #expect(document.title == "The Test Book")
    }

    @Test func encryptedEPUBMetadataIsRejected() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        var builder = TestZIPBuilder()
        addValidEPUBFiles(to: &builder, chapterCompression: .stored)
        builder.add(
            path: "META-INF/rights.xml",
            data: Data("<rights/>".utf8),
            compression: .stored
        )
        try builder.build().write(to: url)

        var caught: BookImportError?
        do {
            _ = try EPUBBookParser.parse(
                url: url,
                bookID: String(repeating: "f", count: 64)
            )
        } catch let error as BookImportError {
            caught = error
        }
        #expect(caught == .protectedEPUB)
    }

    @Test func unsafeArchivePathIsRejectedBeforeExtraction() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        var builder = TestZIPBuilder()
        builder.add(
            path: "mimetype",
            data: Data("application/epub+zip".utf8),
            compression: .stored
        )
        builder.add(
            path: "../outside.xhtml",
            data: Data("bad".utf8),
            compression: .stored
        )
        try builder.build().write(to: url)

        var caught: BookImportError?
        do {
            _ = try EPUBArchive(url: url)
        } catch let error as BookImportError {
            caught = error
        }
        #expect(caught == .unsafeArchive)
    }

    @Test func encryptedZIPEntryIsRejected() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        var builder = TestZIPBuilder()
        builder.add(
            path: "mimetype",
            data: Data("application/epub+zip".utf8),
            compression: .stored,
            encrypted: true
        )
        try builder.build().write(to: url)

        var caught: BookImportError?
        do {
            _ = try EPUBArchive(url: url)
        } catch let error as BookImportError {
            caught = error
        }
        #expect(caught == .protectedEPUB)
    }

    @Test func duplicateArchiveEntryIsRejected() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        var builder = TestZIPBuilder()
        addValidEPUBFiles(to: &builder, chapterCompression: .stored)
        builder.add(
            path: "OEBPS/chapter.xhtml",
            data: Data("duplicate".utf8),
            compression: .stored
        )
        try builder.build().write(to: url)

        var caught: BookImportError?
        do {
            _ = try EPUBArchive(url: url)
        } catch let error as BookImportError {
            caught = error
        }
        #expect(caught == .unsafeArchive)
    }

    @Test func corruptedEntryChecksumIsRejected() throws {
        let url = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = try makeValidEPUB(chapterCompression: .stored)
        let needle = Data("The first EPUB sentence".utf8)
        let range = try #require(data.range(of: needle))
        data[range.lowerBound] ^= 0xff
        try data.write(to: url)

        var caught: BookImportError?
        do {
            _ = try EPUBBookParser.parse(
                url: url,
                bookID: String(repeating: "6", count: 64)
            )
        } catch let error as BookImportError {
            caught = error
        }
        #expect(caught == .invalidEPUB)
    }

    @Test func coordinatorRejectsOversizedSourceBeforeCopyingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let source = temporaryFileURL(extension: "epub")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        #expect(FileManager.default.createFile(atPath: source.path, contents: Data([0])))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(250 * 1024 * 1024 + 1))
        try handle.close()

        let coordinator = BookImportCoordinator(
            repository: LibraryRepository(rootURL: root)
        )
        var caught: BookImportError?
        do {
            _ = try await coordinator.importBook(from: source)
        } catch let error as BookImportError {
            caught = error
        }
        #expect(caught == .bookTooLarge)
    }

    @Test @MainActor func coordinatorImportsPersistsReloadsOpensAndRejectsDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let source = temporaryFileURL(extension: "epub")
        let data = try makeValidEPUB(chapterCompression: .stored)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        try data.write(to: source)
        let repository = LibraryRepository(rootURL: root)
        let coordinator = BookImportCoordinator(repository: repository)

        let document = try await coordinator.importBook(from: source)
        let expectedID = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(document.id == expectedID)

        let storedOriginal = root
            .appendingPathComponent(expectedID)
            .appendingPathComponent("Original/source.epub")
        #expect(try Data(contentsOf: storedOriginal) == data)

        let defaultsName = "VoltaireTests.Import.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let reopened = AppModel(
            repository: LibraryRepository(rootURL: root),
            defaults: defaults
        )
        await reopened.loadLibrary()
        #expect(reopened.document(id: expectedID) == document)
        reopened.open(documentID: expectedID)
        #expect(reopened.path == [.reader(documentID: expectedID)])

        var duplicate: BookImportError?
        do {
            _ = try await coordinator.importBook(from: source)
        } catch let error as BookImportError {
            duplicate = error
        }
        #expect(duplicate == .duplicateBook)
    }

    @Test @MainActor func coordinatorImportsPersistsReloadsAndOpensCleanPDF() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: false
        )
        let source = sourceDirectory.appendingPathComponent("A Readable Original.pdf")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextAuthor as String: "Ada Reader"
        ]
        let data = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
            format: format
        ).pdfData { context in
            context.beginPage()
            ("The first stored PDF sentence. The second one survives reload." as NSString).draw(
                in: CGRect(x: 72, y: 72, width: 468, height: 200),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
            )
        }
        try data.write(to: source)
        let repository = LibraryRepository(rootURL: root)
        let coordinator = BookImportCoordinator(repository: repository)

        let document = try await coordinator.importBook(from: source)
        let expectedID = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(document.id == expectedID)
        #expect(document.title == "A Readable Original")
        #expect(document.author == "Ada Reader")
        #expect(document.sentences.count == 2)

        let storedOriginal = root
            .appendingPathComponent(expectedID)
            .appendingPathComponent("Original/source.pdf")
        #expect(try Data(contentsOf: storedOriginal) == data)

        let defaultsName = "VoltaireTests.PDFImport.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let reopened = AppModel(
            repository: LibraryRepository(rootURL: root),
            defaults: defaults
        )
        await reopened.loadLibrary()
        #expect(reopened.document(id: expectedID) == document)
        reopened.open(documentID: expectedID)
        #expect(reopened.path == [.reader(documentID: expectedID)])
    }

    @Test @MainActor func legacyPDFNamedSourceRepairsOnlyItsTitle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: false
        )
        let source = sourceDirectory.appendingPathComponent("source.pdf")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextAuthor as String: "Jonathan Swift"
        ]
        let data = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
            format: format
        ).pdfData { context in
            context.beginPage()
            ("It is a melancholy object. This sentence preserves the stored text." as NSString)
                .draw(
                    in: CGRect(x: 72, y: 72, width: 468, height: 200),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
                )
        }
        try data.write(to: source)
        let bookID = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let legacyDocument = try PDFBookParser.parse(url: source, bookID: bookID)
        #expect(legacyDocument.title == "source")

        let repository = LibraryRepository(rootURL: root)
        try await repository.install(
            document: legacyDocument,
            originalFileURL: source,
            originalFilename: "A Modest Proposal.pdf"
        )
        let packageURL = root.appendingPathComponent(bookID)
        let manifestURL = packageURL.appendingPathComponent("book.json")
        let installed = try JSONDecoder().decode(
            StoredBookPackage.self,
            from: Data(contentsOf: manifestURL)
        )
        var rawPackage = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        var rawDocument = try #require(rawPackage["document"] as? [String: Any])
        rawPackage["futureRootValue"] = "preserve me"
        rawDocument["futureDocumentValue"] = 42
        rawPackage["document"] = rawDocument
        try JSONSerialization.data(
            withJSONObject: rawPackage,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: manifestURL, options: .atomic)

        let loaded = try await repository.loadDocuments()
        let repaired = try #require(loaded.first)
        let manifestAfterFirstLoad = try Data(contentsOf: manifestURL)
        let persisted = try JSONDecoder().decode(
            StoredBookPackage.self,
            from: manifestAfterFirstLoad
        )
        let loadedAgain = try await repository.loadDocuments()
        let persistedRawPackage = try #require(
            JSONSerialization.jsonObject(with: manifestAfterFirstLoad) as? [String: Any]
        )
        let persistedRawDocument = try #require(
            persistedRawPackage["document"] as? [String: Any]
        )

        #expect(loaded.count == 1)
        #expect(loadedAgain == loaded)
        #expect(repaired.title == "A Modest Proposal")
        #expect(repaired.id == installed.document.id)
        #expect(repaired.author == installed.document.author)
        #expect(repaired.chapterTitle == installed.document.chapterTitle)
        #expect(repaired.sentences == installed.document.sentences)
        #expect(repaired.chapters == installed.document.chapters)
        #expect(persisted.document == repaired)
        #expect(persisted.originalFilename == installed.originalFilename)
        #expect(persisted.importedAt == installed.importedAt)
        #expect(persistedRawPackage["futureRootValue"] as? String == "preserve me")
        #expect(persistedRawDocument["futureDocumentValue"] as? Int == 42)
        #expect(try Data(contentsOf: manifestURL) == manifestAfterFirstLoad)
        #expect(try Data(contentsOf: packageURL.appendingPathComponent("Original/source.pdf")) == data)
    }

    @Test @MainActor func explicitPDFTitleNamedSourceIsNeverRewritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: false
        )
        let source = sourceDirectory.appendingPathComponent("source.pdf")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "source",
            kCGPDFContextAuthor as String: "Named Author"
        ]
        let data = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
            format: format
        ).pdfData { context in
            context.beginPage()
            ("This PDF deliberately uses source as its real title." as NSString).draw(
                in: CGRect(x: 72, y: 72, width: 468, height: 200),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
            )
        }
        try data.write(to: source)
        let bookID = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let document = try PDFBookParser.parse(url: source, bookID: bookID)
        #expect(document.title == "source")

        let repository = LibraryRepository(rootURL: root)
        try await repository.install(
            document: document,
            originalFileURL: source,
            originalFilename: "Different Filename.pdf"
        )
        let manifestURL = root
            .appendingPathComponent(bookID)
            .appendingPathComponent("book.json")
        let manifestBefore = try Data(contentsOf: manifestURL)

        let loaded = try await repository.loadDocuments()

        #expect(loaded == [document])
        #expect(try Data(contentsOf: manifestURL) == manifestBefore)
    }

    @Test func repositoryKeepsOriginalAndReloadsDocument() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let source = temporaryFileURL(extension: "epub")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("immutable original".utf8).write(to: source)
        let repository = LibraryRepository(rootURL: root)
        let document = ReaderDocument(
            id: String(repeating: "1", count: 64),
            title: "Stored Book",
            author: "Stored Author",
            chapterTitle: "Full text",
            sentences: [ReaderSentence(id: "stored-1", text: "Stored sentence.")]
        )

        try await repository.install(
            document: document,
            originalFileURL: source,
            originalFilename: "Stored.epub"
        )
        let loaded = try await repository.loadDocuments()

        #expect(loaded == [document])
        #expect(FileManager.default.fileExists(
            atPath: root
                .appendingPathComponent(document.id)
                .appendingPathComponent("Original/source.epub")
                .path
        ))

        var caught: LibraryRepositoryError?
        do {
            try await repository.install(
                document: document,
                originalFileURL: source,
                originalFilename: "Stored.epub"
            )
        } catch let error as LibraryRepositoryError {
            caught = error
        }
        #expect(caught == .duplicateBook)
    }

    @Test func legacySchemaOneEPUBEnrichesOnlyChapters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let source = temporaryFileURL(extension: "epub")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        let originalData = try makeNavigationEPUB(kind: .epub3)
        try originalData.write(to: source)
        let bookID = SHA256.hash(data: originalData)
            .map { String(format: "%02x", $0) }
            .joined()
        let parsed = try EPUBBookParser.parse(url: source, bookID: bookID)
        let repository = LibraryRepository(rootURL: root)
        try await repository.install(
            document: parsed,
            originalFileURL: source,
            originalFilename: "Legacy.epub"
        )

        let manifestURL = root.appendingPathComponent(bookID).appendingPathComponent("book.json")
        let installed = try JSONDecoder().decode(
            StoredBookPackage.self,
            from: Data(contentsOf: manifestURL)
        )
        let legacyDocument = ReaderDocument(
            id: installed.document.id,
            title: "Stored Legacy Title",
            author: "Stored Legacy Author",
            chapterTitle: "Stored Legacy Heading",
            sentences: installed.document.sentences
        )
        let legacy = StoredBookPackage(
            schemaVersion: installed.schemaVersion,
            document: legacyDocument,
            originalFilename: installed.originalFilename,
            importedAt: installed.importedAt
        )
        try encodedPackageWithoutChapters(legacy).write(to: manifestURL, options: .atomic)

        let loaded = try await repository.loadDocuments()
        let enriched = try #require(loaded.first)
        let manifestAfterEnrichment = try Data(contentsOf: manifestURL)
        let persisted = try JSONDecoder().decode(
            StoredBookPackage.self,
            from: manifestAfterEnrichment
        )
        let loadedAgain = try await repository.loadDocuments()

        #expect(loaded.count == 1)
        #expect(enriched.id == legacyDocument.id)
        #expect(enriched.title == legacyDocument.title)
        #expect(enriched.author == legacyDocument.author)
        #expect(enriched.chapterTitle == legacyDocument.chapterTitle)
        #expect(enriched.sentences == legacyDocument.sentences)
        #expect(enriched.chapters == parsed.chapters)
        #expect(persisted.schemaVersion == 1)
        #expect(persisted.originalFilename == installed.originalFilename)
        #expect(persisted.importedAt == installed.importedAt)
        #expect(persisted.document == enriched)
        #expect(loadedAgain == loaded)
        #expect(try Data(contentsOf: manifestURL) == manifestAfterEnrichment)
        #expect(!persisted.document.chapters.contains { $0.title == "Start" })
        #expect(persisted.document.navigationChapters.first?.title == "Chapter One")
        #expect(try Data(contentsOf: root
            .appendingPathComponent(bookID)
            .appendingPathComponent("Original/source.epub")) == originalData)
    }

    @Test func legacyEPUBWithMissingOriginalRemainsVisibleAndUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let source = temporaryFileURL(extension: "epub")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        let originalData = try makeNavigationEPUB(kind: .epub3)
        try originalData.write(to: source)
        let bookID = SHA256.hash(data: originalData)
            .map { String(format: "%02x", $0) }
            .joined()
        let parsed = try EPUBBookParser.parse(url: source, bookID: bookID)
        let legacyDocument = ReaderDocument(
            id: parsed.id,
            title: parsed.title,
            author: parsed.author,
            chapterTitle: parsed.chapterTitle,
            sentences: parsed.sentences
        )
        let repository = LibraryRepository(rootURL: root)
        try await repository.install(
            document: legacyDocument,
            originalFileURL: source,
            originalFilename: "Missing.epub"
        )
        let packageURL = root.appendingPathComponent(bookID)
        let manifestURL = packageURL.appendingPathComponent("book.json")
        try FileManager.default.removeItem(
            at: packageURL.appendingPathComponent("Original/source.epub")
        )
        let manifestBefore = try Data(contentsOf: manifestURL)

        let loaded = try await repository.loadDocuments()

        #expect(loaded == [legacyDocument])
        #expect(loaded[0].chapters.isEmpty)
        #expect(loaded[0].navigationChapters.count == 1)
        #expect(try Data(contentsOf: manifestURL) == manifestBefore)
    }

    @Test func legacyEPUBSentenceMismatchIsNeverRewrittenOrHidden() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let source = temporaryFileURL(extension: "epub")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        let originalData = try makeNavigationEPUB(kind: .epub3)
        try originalData.write(to: source)
        let bookID = SHA256.hash(data: originalData)
            .map { String(format: "%02x", $0) }
            .joined()
        let parsed = try EPUBBookParser.parse(url: source, bookID: bookID)
        var changedSentences = parsed.sentences
        changedSentences[0] = ReaderSentence(
            id: changedSentences[0].id,
            text: "Stored legacy wording."
        )
        let changedDocument = ReaderDocument(
            id: parsed.id,
            title: parsed.title,
            author: parsed.author,
            chapterTitle: parsed.chapterTitle,
            sentences: changedSentences
        )
        let repository = LibraryRepository(rootURL: root)
        try await repository.install(
            document: changedDocument,
            originalFileURL: source,
            originalFilename: "Mismatch.epub"
        )
        let manifestURL = root.appendingPathComponent(bookID).appendingPathComponent("book.json")
        let manifestBefore = try Data(contentsOf: manifestURL)

        let loaded = try await repository.loadDocuments()

        #expect(loaded == [changedDocument])
        #expect(loaded[0].chapters.isEmpty)
        #expect(try Data(contentsOf: manifestURL) == manifestBefore)
    }
}

private func temporaryFileURL(extension fileExtension: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(fileExtension)
}

private func encodedPackage(_ package: StoredBookPackage) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(package)
}

private func encodedPackageWithoutChapters(_ package: StoredBookPackage) throws -> Data {
    let encoded = try encodedPackage(package)
    guard var root = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
          var document = root["document"] as? [String: Any] else {
        throw ImportTestFixtureError.invalidPackageJSON
    }
    document.removeValue(forKey: "chapters")
    root["document"] = document
    return try JSONSerialization.data(
        withJSONObject: root,
        options: [.prettyPrinted, .sortedKeys]
    )
}

private enum ImportTestFixtureError: Error {
    case invalidPackageJSON
}

private func makeValidEPUB(chapterCompression: TestZIPBuilder.Compression) throws -> Data {
    var builder = TestZIPBuilder()
    addValidEPUBFiles(to: &builder, chapterCompression: chapterCompression)
    return try builder.build()
}

private func addValidEPUBFiles(
    to builder: inout TestZIPBuilder,
    chapterCompression: TestZIPBuilder.Compression,
    chapterXHTML: String? = nil
) {
    builder.add(
        path: "mimetype",
        data: Data("application/epub+zip".utf8),
        compression: .stored
    )
    builder.add(
        path: "META-INF/container.xml",
        data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.utf8),
        compression: .stored
    )
    builder.add(
        path: "OEBPS/content.opf",
        data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>The Test Book</dc:title><dc:creator>Grace Author</dc:creator>
          </metadata>
          <manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
          <spine><itemref idref="chapter"/></spine>
        </package>
        """.utf8),
        compression: .stored
    )
    builder.add(
        path: "OEBPS/chapter.xhtml",
        data: Data((chapterXHTML ?? """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Ignore</title></head><body>
          <h1>Chapter One</h1><p>The first EPUB sentence. The second EPUB sentence.</p>
        </body></html>
        """).utf8),
        compression: chapterCompression
    )
}

private enum NavigationEPUBKind: Equatable {
    case epub3
    case ncx
    case brokenEPUB3
}

private func makeNavigationEPUB(kind: NavigationEPUBKind) throws -> Data {
    var builder = TestZIPBuilder()
    builder.add(
        path: "mimetype",
        data: Data("application/epub+zip".utf8),
        compression: .stored
    )
    builder.add(
        path: "META-INF/container.xml",
        data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.utf8),
        compression: .stored
    )

    let navigationManifest: String
    let spineAttribute: String
    switch kind {
    case .epub3, .brokenEPUB3:
        navigationManifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"
        spineAttribute = ""
    case .ncx:
        navigationManifest = "<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>"
        spineAttribute = " toc=\"ncx\""
    }
    builder.add(
        path: "OEBPS/content.opf",
        data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Navigation Test</dc:title><dc:creator>Grace Author</dc:creator>
          </metadata>
          <manifest>
            <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
            \(navigationManifest)
          </manifest>
          <spine\(spineAttribute)><itemref idref="chapter"/></spine>
        </package>
        """.utf8),
        compression: .stored
    )
    builder.add(
        path: "OEBPS/chapter.xhtml",
        data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
          <h1 id="one">Chapter One</h1><p>The first chapter sentence.</p>
          <h2 id="two">Chapter Two</h2><p>The second chapter sentence.</p>
        </body></html>
        """.utf8),
        compression: .stored
    )

    switch kind {
    case .epub3, .brokenEPUB3:
        let firstFragment = kind == .brokenEPUB3 ? "missing-one" : "one"
        let secondFragment = kind == .brokenEPUB3 ? "missing-two" : "two"
        builder.add(
            path: "OEBPS/nav.xhtml",
            data: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
              <body>
                <nav epub:type="page-list"><ol><li><a href="chapter.xhtml#two">Ignored page</a></li></ol></nav>
                <nav epub:type="toc" role="navigation doc-toc"><ol>
                  <li><a href="chapter.xhtml#\(firstFragment)">Chapter One</a><ol>
                    <li><a href="chapter.xhtml#\(secondFragment)">Chapter Two</a></li>
                  </ol></li>
                </ol></nav>
              </body>
            </html>
            """.utf8),
            compression: .stored
        )
    case .ncx:
        builder.add(
            path: "OEBPS/toc.ncx",
            data: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
              <navMap>
                <navPoint id="one"><navLabel><text>Chapter One</text></navLabel><content src="chapter.xhtml#one"/>
                  <navPoint id="two"><navLabel><text>Chapter Two</text></navLabel><content src="chapter.xhtml#two"/></navPoint>
                </navPoint>
              </navMap>
            </ncx>
            """.utf8),
            compression: .stored
        )
    }
    return try builder.build()
}

private struct TestZIPBuilder {
    enum Compression {
        case stored
        case deflated

        var method: UInt16 { self == .stored ? 0 : 8 }
    }

    private struct SourceEntry {
        let path: String
        let data: Data
        let compression: Compression
        let encrypted: Bool
    }

    private struct EncodedEntry {
        let source: SourceEntry
        let compressed: Data
        let checksum: UInt32
        let localOffset: Int
    }

    private var entries: [SourceEntry] = []

    mutating func add(
        path: String,
        data: Data,
        compression: Compression,
        encrypted: Bool = false
    ) {
        entries.append(.init(
            path: path,
            data: data,
            compression: compression,
            encrypted: encrypted
        ))
    }

    func build() throws -> Data {
        var archive = Data()
        var encodedEntries: [EncodedEntry] = []
        for source in entries {
            let compressed = source.compression == .stored
                ? source.data
                : try rawDeflate(source.data)
            let checksum = crc32(source.data)
            let localOffset = archive.count
            let name = Data(source.path.utf8)
            archive.appendUInt32LE(0x04034b50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(source.encrypted ? 1 : 0)
            archive.appendUInt16LE(source.compression.method)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(checksum)
            archive.appendUInt32LE(UInt32(compressed.count))
            archive.appendUInt32LE(UInt32(source.data.count))
            archive.appendUInt16LE(UInt16(name.count))
            archive.appendUInt16LE(0)
            archive.append(name)
            archive.append(compressed)
            encodedEntries.append(.init(
                source: source,
                compressed: compressed,
                checksum: checksum,
                localOffset: localOffset
            ))
        }

        let centralOffset = archive.count
        var central = Data()
        for entry in encodedEntries {
            let name = Data(entry.source.path.utf8)
            central.appendUInt32LE(0x02014b50)
            central.appendUInt16LE(20)
            central.appendUInt16LE(20)
            central.appendUInt16LE(entry.source.encrypted ? 1 : 0)
            central.appendUInt16LE(entry.source.compression.method)
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt32LE(entry.checksum)
            central.appendUInt32LE(UInt32(entry.compressed.count))
            central.appendUInt32LE(UInt32(entry.source.data.count))
            central.appendUInt16LE(UInt16(name.count))
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt16LE(0)
            central.appendUInt32LE(0)
            central.appendUInt32LE(UInt32(entry.localOffset))
            central.append(name)
        }
        archive.append(central)
        archive.appendUInt32LE(0x06054b50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(encodedEntries.count))
        archive.appendUInt16LE(UInt16(encodedEntries.count))
        archive.appendUInt32LE(UInt32(central.count))
        archive.appendUInt32LE(UInt32(centralOffset))
        archive.appendUInt16LE(0)
        return archive
    }

    private func rawDeflate(_ data: Data) throws -> Data {
        if data.isEmpty { return Data([0x03, 0x00]) }
        var capacity = max(data.count * 2 + 64, 128)
        while capacity <= data.count * 8 + 1024 {
            var output = Data(count: capacity)
            let outputCount = output.withUnsafeMutableBytes { destination in
                data.withUnsafeBytes { source in
                    compression_encode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!,
                        capacity,
                        source.bindMemory(to: UInt8.self).baseAddress!,
                        data.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if outputCount > 0 {
                output.count = outputCount
                return output
            }
            capacity *= 2
        }
        throw BookImportError.invalidEPUB
    }

    private func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xffff_ffff
        for byte in data {
            var current = (value ^ UInt32(byte)) & 0xff
            for _ in 0..<8 {
                current = (current & 1) == 1
                    ? (current >> 1) ^ 0xedb8_8320
                    : current >> 1
            }
            value = (value >> 8) ^ current
        }
        return value ^ 0xffff_ffff
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
