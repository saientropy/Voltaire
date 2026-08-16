import Compression
import Foundation

private enum ArchiveReadError: Error {
    case outOfBounds
}

struct EPUBArchive {
    struct Entry {
        let path: String
        let compressionMethod: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private static let maximumArchiveBytes = 250 * 1024 * 1024
    private static let maximumEntryBytes = 64 * 1024 * 1024
    private static let maximumTotalBytes = 512 * 1024 * 1024
    private static let maximumEntries = 20_000

    private let data: Data
    private let entries: [String: Entry]

    init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else { throw BookImportError.invalidEPUB }
        guard fileSize <= Self.maximumArchiveBytes else { throw BookImportError.bookTooLarge }
        let archiveData = try Data(contentsOf: url, options: [.mappedIfSafe])
        self.data = archiveData
        self.entries = try Self.readCentralDirectory(from: archiveData)
    }

    func contains(_ path: String) -> Bool {
        entries[path] != nil
    }

    func entry(for path: String) -> Entry? {
        entries[path]
    }

    func fileData(at path: String) throws -> Data {
        guard let entry = entries[path] else {
            throw BookImportError.invalidEPUB
        }
        let offset = entry.localHeaderOffset
        guard try data.uint32LE(at: offset) == 0x04034b50 else {
            throw BookImportError.invalidEPUB
        }
        let nameLength = Int(try data.uint16LE(at: offset + 26))
        let extraLength = Int(try data.uint16LE(at: offset + 28))
        let payloadStart = offset + 30 + nameLength + extraLength
        let payloadEnd = payloadStart + entry.compressedSize
        guard payloadStart >= 0, payloadEnd <= data.count else {
            throw BookImportError.invalidEPUB
        }
        let compressed = Data(data[payloadStart..<payloadEnd])

        let decoded: Data
        switch entry.compressionMethod {
        case 0:
            guard compressed.count == entry.uncompressedSize else {
                throw BookImportError.invalidEPUB
            }
            decoded = compressed
        case 8:
            decoded = try Self.inflateRawDeflate(
                compressed,
                expectedByteCount: entry.uncompressedSize
            )
        default:
            throw BookImportError.unsupportedArchive
        }

        guard Self.crc32(decoded) == entry.crc32 else {
            throw BookImportError.invalidEPUB
        }
        return decoded
    }

    private static func readCentralDirectory(from data: Data) throws -> [String: Entry] {
        guard data.count >= 22 else { throw BookImportError.invalidEPUB }
        let searchStart = max(0, data.count - 65_557)
        var cursor = data.count - 22
        var endOffset: Int?
        while cursor >= searchStart {
            if (try? data.uint32LE(at: cursor)) == 0x06054b50 {
                endOffset = cursor
                break
            }
            if cursor == searchStart { break }
            cursor -= 1
        }
        guard let endOffset else { throw BookImportError.invalidEPUB }

        let diskNumber = try data.uint16LE(at: endOffset + 4)
        let centralDisk = try data.uint16LE(at: endOffset + 6)
        let entriesOnDisk = try data.uint16LE(at: endOffset + 8)
        let totalEntries = try data.uint16LE(at: endOffset + 10)
        let centralSize = try data.uint32LE(at: endOffset + 12)
        let centralOffset = try data.uint32LE(at: endOffset + 16)
        guard diskNumber == 0,
              centralDisk == 0,
              entriesOnDisk == totalEntries,
              totalEntries != .max,
              centralSize != .max,
              centralOffset != .max else {
            throw BookImportError.unsupportedArchive
        }
        guard Int(totalEntries) <= maximumEntries else {
            throw BookImportError.bookTooLarge
        }

        let directoryStart = Int(centralOffset)
        let directoryEnd = directoryStart + Int(centralSize)
        guard directoryStart >= 0,
              directoryEnd <= data.count,
              directoryEnd <= endOffset else {
            throw BookImportError.invalidEPUB
        }

        var result: [String: Entry] = [:]
        var totalUncompressed = 0
        var entryOffset = directoryStart
        for _ in 0..<Int(totalEntries) {
            guard try data.uint32LE(at: entryOffset) == 0x02014b50 else {
                throw BookImportError.invalidEPUB
            }
            let versionMadeBy = try data.uint16LE(at: entryOffset + 4)
            let flags = try data.uint16LE(at: entryOffset + 8)
            let method = try data.uint16LE(at: entryOffset + 10)
            let checksum = try data.uint32LE(at: entryOffset + 16)
            let compressedSize = try data.uint32LE(at: entryOffset + 20)
            let uncompressedSize = try data.uint32LE(at: entryOffset + 24)
            let nameLength = Int(try data.uint16LE(at: entryOffset + 28))
            let extraLength = Int(try data.uint16LE(at: entryOffset + 30))
            let commentLength = Int(try data.uint16LE(at: entryOffset + 32))
            let startingDisk = try data.uint16LE(at: entryOffset + 34)
            let externalAttributes = try data.uint32LE(at: entryOffset + 38)
            let localOffset = try data.uint32LE(at: entryOffset + 42)
            guard compressedSize != .max,
                  uncompressedSize != .max,
                  localOffset != .max,
                  startingDisk == 0 else {
                throw BookImportError.unsupportedArchive
            }
            guard flags & 0x1 == 0 else {
                throw BookImportError.protectedEPUB
            }
            guard method == 0 || method == 8 else {
                throw BookImportError.unsupportedArchive
            }

            let nameStart = entryOffset + 46
            let nameEnd = nameStart + nameLength
            guard nameStart >= 0, nameEnd <= directoryEnd else {
                throw BookImportError.invalidEPUB
            }
            let nameData = Data(data[nameStart..<nameEnd])
            guard let rawName = String(data: nameData, encoding: .utf8),
                  let path = safeStoredPath(rawName) else {
                throw BookImportError.unsafeArchive
            }

            let madeBySystem = UInt8(versionMadeBy >> 8)
            if madeBySystem == 3 {
                let unixMode = UInt16((externalAttributes >> 16) & 0xffff)
                if unixMode & 0xf000 == 0xa000 {
                    throw BookImportError.unsafeArchive
                }
            }

            let uncompressedCount = Int(uncompressedSize)
            let compressedCount = Int(compressedSize)
            guard uncompressedCount <= maximumEntryBytes else {
                throw BookImportError.bookTooLarge
            }
            if uncompressedCount > 0 {
                guard compressedCount > 0,
                      uncompressedCount <= max(compressedCount * 500, 1_048_576) else {
                    throw BookImportError.bookTooLarge
                }
            }
            totalUncompressed += uncompressedCount
            guard totalUncompressed <= maximumTotalBytes else {
                throw BookImportError.bookTooLarge
            }

            if !rawName.hasSuffix("/") {
                guard result[path] == nil else {
                    throw BookImportError.unsafeArchive
                }
                result[path] = Entry(
                    path: path,
                    compressionMethod: method,
                    crc32: checksum,
                    compressedSize: compressedCount,
                    uncompressedSize: uncompressedCount,
                    localHeaderOffset: Int(localOffset)
                )
            }

            entryOffset = nameEnd + extraLength + commentLength
            guard entryOffset <= directoryEnd else {
                throw BookImportError.invalidEPUB
            }
        }
        return result
    }

    private static func safeStoredPath(_ rawPath: String) -> String? {
        guard !rawPath.isEmpty,
              !rawPath.hasPrefix("/"),
              !rawPath.contains("\\"),
              !rawPath.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return nil
        }
        let components = rawPath.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            return nil
        }
        return components.joined(separator: "/")
    }

    private static func inflateRawDeflate(
        _ compressed: Data,
        expectedByteCount: Int
    ) throws -> Data {
        guard expectedByteCount >= 0, expectedByteCount <= maximumEntryBytes else {
            throw BookImportError.bookTooLarge
        }
        if expectedByteCount == 0 {
            return Data()
        }
        let outputCapacity = expectedByteCount + 1
        let compressedByteCount = compressed.count
        var output = Data(count: outputCapacity)
        let decoded: Int = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                guard let destinationAddress = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceAddress = source.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    destinationAddress,
                    outputCapacity,
                    sourceAddress,
                    compressedByteCount,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded == expectedByteCount else {
            throw BookImportError.invalidEPUB
        }
        output.count = decoded
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
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

enum EPUBBookParser {
    private struct ParsedContent {
        let path: String
        let xhtml: ParsedXHTML
        let firstSentenceIDsByBlock: [String?]

        var firstSentenceID: String? {
            firstSentenceIDsByBlock.compactMap { $0 }.first
        }

        func firstSentenceID(atOrAfter blockIndex: Int) -> String? {
            guard blockIndex >= 0, blockIndex < firstSentenceIDsByBlock.count else {
                return nil
            }
            return firstSentenceIDsByBlock[blockIndex...].compactMap { $0 }.first
        }
    }

    private struct ResolvedReference {
        let path: String
        let fragment: String?
    }

    private struct ChapterDraft {
        let title: String
        let level: Int
        let startSentenceID: String
    }

    static func parse(url: URL, bookID: String) throws -> ReaderDocument {
        let archive: EPUBArchive
        do {
            archive = try EPUBArchive(url: url)
        } catch let error as BookImportError {
            throw error
        } catch {
            throw BookImportError.invalidEPUB
        }

        guard let mimetypeEntry = archive.entry(for: "mimetype"),
              mimetypeEntry.compressionMethod == 0,
              let mimetype = String(data: try archive.fileData(at: "mimetype"), encoding: .utf8),
              mimetype == "application/epub+zip" else {
            throw BookImportError.invalidEPUB
        }
        if archive.contains("META-INF/rights.xml") {
            throw BookImportError.protectedEPUB
        }

        let containerData = try archive.fileData(at: "META-INF/container.xml")
        guard let packagePath = ContainerXMLParser.packagePath(from: containerData) else {
            throw BookImportError.invalidEPUB
        }
        let packageData = try archive.fileData(at: packagePath)
        guard let package = OPFXMLParser.parse(packageData) else {
            throw BookImportError.invalidEPUB
        }

        var contentPaths: [String] = []
        if !package.spineIDs.isEmpty {
            for id in package.spineIDs {
                guard let item = package.manifest[id],
                      item.mediaType == "application/xhtml+xml" || item.mediaType == "text/html",
                      let resolved = resolve(item.href, relativeTo: packagePath),
                      archive.contains(resolved) else {
                    throw BookImportError.invalidEPUB
                }
                contentPaths.append(resolved)
            }
        }
        if contentPaths.isEmpty {
            contentPaths = package.manifest.values
                .filter { $0.mediaType == "application/xhtml+xml" || $0.mediaType == "text/html" }
                .compactMap { resolve($0.href, relativeTo: packagePath) }
                .sorted()
        }
        guard !contentPaths.isEmpty, contentPaths.count <= 20_000 else {
            throw BookImportError.noReadableText
        }
        try validateEncryption(
            in: archive,
            contentPaths: Set(contentPaths)
        )

        var contents: [ParsedContent] = []
        var sentences: [ReaderSentence] = []
        var firstHeading: String?
        var characterCount = 0
        for path in contentPaths {
            let contentData = try archive.fileData(at: path)
            guard let parsed = XHTMLTextParser.parse(contentData) else {
                throw BookImportError.invalidEPUB
            }
            if firstHeading == nil {
                firstHeading = parsed.firstHeading
            }
            for block in parsed.blocks {
                characterCount += block.count
                guard characterCount <= 20_000_000 else {
                    throw BookImportError.bookTooLarge
                }
            }
            let processed = BookTextProcessor.processSentences(
                blocks: parsed.blocks,
                bookID: bookID,
                startingAt: sentences.count
            )
            sentences.append(contentsOf: processed.sentences)
            contents.append(ParsedContent(
                path: path,
                xhtml: parsed,
                firstSentenceIDsByBlock: processed.firstSentenceIDsByBlock
            ))
        }

        guard !sentences.isEmpty else {
            throw BookImportError.noReadableText
        }
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let resolvedChapterTitle = clean(firstHeading, fallback: "Full text")
        let chapters = makeChapters(
            archive: archive,
            package: package,
            packagePath: packagePath,
            contents: contents,
            sentences: sentences,
            bookID: bookID,
            fallbackTitle: resolvedChapterTitle
        )
        return ReaderDocument(
            id: bookID,
            title: clean(package.title, fallback: fallbackTitle),
            author: clean(package.creators.joined(separator: ", "), fallback: "Unknown author"),
            chapterTitle: resolvedChapterTitle,
            sentences: sentences,
            chapters: chapters
        )
    }

    private static func resolve(_ href: String, relativeTo packagePath: String) -> String? {
        resolveReference(href, relativeTo: packagePath)?.path
    }

    private static func resolveReference(
        _ href: String,
        relativeTo baseFilePath: String
    ) -> ResolvedReference? {
        let referenceParts = href.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let rawPath = referenceParts.first.map(String.init) ?? ""
        let queryless = rawPath.split(
            separator: "?",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? rawPath
        guard let decodedPath = queryless.removingPercentEncoding,
              !decodedPath.hasPrefix("/"),
              !decodedPath.contains("\\"),
              decodedPath.split(separator: "/").first?.contains(":") != true,
              !decodedPath.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return nil
        }

        let resolvedPath: String
        if decodedPath.isEmpty {
            resolvedPath = baseFilePath
        } else {
            var components = baseFilePath
                .split(separator: "/")
                .dropLast()
                .map(String.init)
            for component in decodedPath
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init) {
                switch component {
                case ".":
                    continue
                case "..":
                    guard !components.isEmpty else { return nil }
                    components.removeLast()
                default:
                    components.append(component)
                }
            }
            guard !components.isEmpty else { return nil }
            resolvedPath = components.joined(separator: "/")
        }

        let fragment: String?
        if referenceParts.count == 2 {
            let rawFragment = String(referenceParts[1])
            guard let decodedFragment = rawFragment.removingPercentEncoding,
                  !decodedFragment.unicodeScalars.contains(where: { $0.value == 0 }) else {
                return nil
            }
            fragment = decodedFragment.isEmpty ? nil : decodedFragment
        } else {
            fragment = nil
        }
        return ResolvedReference(path: resolvedPath, fragment: fragment)
    }

    private static func makeChapters(
        archive: EPUBArchive,
        package: EPUBPackage,
        packagePath: String,
        contents: [ParsedContent],
        sentences: [ReaderSentence],
        bookID: String,
        fallbackTitle: String
    ) -> [ReaderChapter] {
        let sentenceIndices = Dictionary(
            uniqueKeysWithValues: sentences.enumerated().map { ($0.element.id, $0.offset) }
        )
        var contentsByPath: [String: ParsedContent] = [:]
        for content in contents where contentsByPath[content.path] == nil {
            contentsByPath[content.path] = content
        }

        var drafts: [ChapterDraft] = []
        for navigation in navigationSources(
            archive: archive,
            package: package,
            packagePath: packagePath
        ) {
            var mappedDrafts: [ChapterDraft] = []
            for entry in navigation.entries {
                guard let title = cleanChapterTitle(entry.title),
                      let reference = resolveReference(entry.href, relativeTo: navigation.path),
                      let content = contentsByPath[reference.path] else {
                    continue
                }
                let targetID: String?
                if let fragment = reference.fragment {
                    guard let blockIndex = content.xhtml.anchorBlockIndices[fragment] else {
                        continue
                    }
                    targetID = content.firstSentenceID(atOrAfter: blockIndex)
                } else {
                    targetID = content.firstSentenceID
                }
                guard let targetID else { continue }
                mappedDrafts.append(ChapterDraft(
                    title: title,
                    level: min(max(entry.level, 0), 3),
                    startSentenceID: targetID
                ))
            }
            if !mappedDrafts.isEmpty {
                drafts = mappedDrafts
                break
            }
        }

        if drafts.isEmpty {
            for content in contents {
                for heading in content.xhtml.headings {
                    guard let title = cleanChapterTitle(heading.title),
                          let targetID = content.firstSentenceID(atOrAfter: heading.blockIndex) else {
                        continue
                    }
                    drafts.append(ChapterDraft(
                        title: title,
                        level: min(max(heading.level, 0), 3),
                        startSentenceID: targetID
                    ))
                }
            }
        }

        if drafts.isEmpty {
            for (index, content) in contents.enumerated() {
                guard let targetID = content.firstSentenceID else { continue }
                let title = cleanChapterTitle(content.xhtml.firstHeading)
                    ?? (contents.count == 1 ? fallbackTitle : "Section \(index + 1)")
                drafts.append(ChapterDraft(
                    title: title,
                    level: 0,
                    startSentenceID: targetID
                ))
            }
        }

        var accepted: [ChapterDraft] = []
        var seenStarts: Set<String> = []
        var lastSentenceIndex = -1
        for draft in drafts {
            guard let index = sentenceIndices[draft.startSentenceID],
                  index > lastSentenceIndex,
                  seenStarts.insert(draft.startSentenceID).inserted else {
                continue
            }
            accepted.append(draft)
            lastSentenceIndex = index
        }

        if accepted.isEmpty, let firstSentence = sentences.first {
            accepted = [ChapterDraft(
                title: fallbackTitle,
                level: 0,
                startSentenceID: firstSentence.id
            )]
        }

        let prefix = String(bookID.prefix(12))
        return accepted.enumerated().map { index, draft in
            ReaderChapter(
                id: "\(prefix)-section-\(String(format: "%04d", index + 1))",
                title: draft.title,
                level: draft.level,
                startSentenceID: draft.startSentenceID
            )
        }
    }

    private static func navigationSources(
        archive: EPUBArchive,
        package: EPUBPackage,
        packagePath: String
    ) -> [(entries: [EPUBNavigationEntry], path: String)] {
        let manifestItems = package.manifest.sorted { $0.key < $1.key }
        var sources: [(entries: [EPUBNavigationEntry], path: String)] = []
        var seenPaths: Set<String> = []
        for (_, item) in manifestItems where item.properties.contains("nav") {
            guard let path = resolve(item.href, relativeTo: packagePath),
                  seenPaths.insert(path).inserted,
                  archive.contains(path),
                  let data = try? archive.fileData(at: path),
                  let entries = EPUB3NavigationParser.parse(data),
                  !entries.isEmpty else {
                continue
            }
            sources.append((entries, path))
        }

        var ncxItems: [EPUBPackage.Item] = []
        if let spineTOCID = package.spineTOCID,
           let item = package.manifest[spineTOCID] {
            ncxItems.append(item)
        }
        ncxItems.append(contentsOf: manifestItems.compactMap { _, item in
            item.mediaType == "application/x-dtbncx+xml" ? item : nil
        })
        for item in ncxItems {
            guard let path = resolve(item.href, relativeTo: packagePath),
                  seenPaths.insert(path).inserted,
                  archive.contains(path),
                  let data = try? archive.fileData(at: path),
                  let entries = NCXNavigationParser.parse(data),
                  !entries.isEmpty else {
                continue
            }
            sources.append((entries, path))
        }
        return sources
    }

    private static func cleanChapterTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = BookTextProcessor.normalize(value)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(300))
    }

    private static func clean(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        let normalized = BookTextProcessor.normalize(value)
        return normalized.isEmpty ? fallback : normalized
    }

    private static func validateEncryption(
        in archive: EPUBArchive,
        contentPaths: Set<String>
    ) throws {
        guard archive.contains("META-INF/encryption.xml") else { return }
        let data = try archive.fileData(at: "META-INF/encryption.xml")
        guard let entries = EncryptionXMLParser.parse(data), !entries.isEmpty else {
            throw BookImportError.protectedEPUB
        }

        let fontAlgorithms: Set<String> = [
            "http://www.idpf.org/2008/embedding",
            "http://ns.adobe.com/pdf/enc#RC"
        ]
        let fontExtensions: Set<String> = ["otf", "ttf", "woff", "woff2"]
        for entry in entries {
            let candidates = [
                normalizedRootPath(entry.uri),
                resolve(entry.uri, relativeTo: "META-INF/encryption.xml")
            ].compactMap { $0 }
            guard fontAlgorithms.contains(entry.algorithm),
                  let target = candidates.first(where: { archive.contains($0) }),
                  fontExtensions.contains((target as NSString).pathExtension.lowercased()),
                  !contentPaths.contains(target) else {
                throw BookImportError.protectedEPUB
            }
        }
    }

    private static func normalizedRootPath(_ rawPath: String) -> String? {
        let pathPart = rawPath.split(separator: "#", maxSplits: 1).first.map(String.init) ?? rawPath
        let queryless = pathPart.split(separator: "?", maxSplits: 1).first.map(String.init) ?? pathPart
        guard let decoded = queryless.removingPercentEncoding,
              !decoded.hasPrefix("/"),
              !decoded.contains("\\") else {
            return nil
        }
        let components = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            return nil
        }
        return components.joined(separator: "/")
    }
}

private struct EPUBEncryptionEntry {
    let algorithm: String
    let uri: String
}

private final class EncryptionXMLParser: NSObject, XMLParserDelegate {
    private var entries: [EPUBEncryptionEntry] = []
    private var algorithm: String?
    private var uri: String?
    private var encryptedDataDepth = 0

    static func parse(_ data: Data) -> [EPUBEncryptionEntry]? {
        let delegate = EncryptionXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(elementName) {
        case "encrypteddata":
            encryptedDataDepth += 1
            if encryptedDataDepth == 1 {
                algorithm = nil
                uri = nil
            }
        case "encryptionmethod" where encryptedDataDepth > 0:
            algorithm = attributeDict["Algorithm"] ?? attributeDict["algorithm"]
        case "cipherreference" where encryptedDataDepth > 0:
            uri = attributeDict["URI"] ?? attributeDict["uri"]
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard localName(elementName) == "encrypteddata", encryptedDataDepth > 0 else {
            return
        }
        if encryptedDataDepth == 1, let algorithm, let uri {
            entries.append(.init(algorithm: algorithm, uri: uri))
        }
        encryptedDataDepth -= 1
    }
}

private struct EPUBPackage {
    struct Item {
        let href: String
        let mediaType: String
        let properties: Set<String>
    }

    var title = ""
    var creators: [String] = []
    var manifest: [String: Item] = [:]
    var spineIDs: [String] = []
    var spineTOCID: String?
}

private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    private(set) var packagePath: String?

    static func packagePath(from data: Data) -> String? {
        let delegate = ContainerXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let path = delegate.packagePath else { return nil }
        return path
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard localName(elementName) == "rootfile",
              let rawPath = attributeDict["full-path"],
              !rawPath.hasPrefix("/"),
              !rawPath.contains("\\"),
              !rawPath.split(separator: "/").contains("..") else {
            return
        }
        packagePath = rawPath
    }
}

private final class OPFXMLParser: NSObject, XMLParserDelegate {
    private var package = EPUBPackage()
    private var capture: String?
    private var text = ""

    static func parse(_ data: Data) -> EPUBPackage? {
        let delegate = OPFXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.package
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(elementName) {
        case "title", "creator":
            capture = localName(elementName)
            text = ""
        case "item":
            guard let id = attributeDict["id"],
                  let href = attributeDict["href"],
                  let mediaType = attributeDict["media-type"] else { return }
            let properties = Set(
                (attributeDict["properties"] ?? "")
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            )
            package.manifest[id] = .init(
                href: href,
                mediaType: mediaType,
                properties: properties
            )
        case "spine":
            package.spineTOCID = attributeDict["toc"]
        case "itemref":
            if let idref = attributeDict["idref"] {
                package.spineIDs.append(idref)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capture != nil else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        guard capture == name else { return }
        let normalized = BookTextProcessor.normalize(text)
        if name == "title", package.title.isEmpty {
            package.title = normalized
        } else if name == "creator", !normalized.isEmpty {
            package.creators.append(normalized)
        }
        capture = nil
        text = ""
    }
}

private struct EPUBNavigationEntry {
    let title: String
    let href: String
    let level: Int
}

private final class EPUB3NavigationParser: NSObject, XMLParserDelegate {
    private var entries: [EPUBNavigationEntry] = []
    private var tocDepth = 0
    private var listDepth = 0
    private var linkDepth = 0
    private var linkHref: String?
    private var linkText = ""

    static func parse(_ data: Data) -> [EPUBNavigationEntry]? {
        let delegate = EPUB3NavigationParser()
        let parser = XMLParser(data: XHTMLTextParser.sanitize(data))
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        if name == "nav" {
            let type = attributeDict["epub:type"] ?? attributeDict["type"] ?? ""
            let role = attributeDict["role"] ?? ""
            if tocDepth > 0 ||
                type.split(whereSeparator: \.isWhitespace).contains("toc") ||
                role.split(whereSeparator: \.isWhitespace).contains("doc-toc") {
                tocDepth += 1
            }
            return
        }
        guard tocDepth > 0 else { return }
        if name == "ol" {
            listDepth += 1
        } else if name == "a", linkDepth == 0 {
            linkDepth = 1
            linkHref = attributeDict["href"]
            linkText = ""
        } else if linkDepth > 0 {
            linkDepth += 1
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard linkDepth > 0 else { return }
        linkText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        if linkDepth > 0 {
            linkDepth -= 1
            if name == "a", linkDepth == 0 {
                let title = BookTextProcessor.normalize(linkText)
                if let linkHref,
                   !title.isEmpty,
                   entries.count < 20_000 {
                    entries.append(.init(
                        title: title,
                        href: linkHref,
                        level: max(listDepth - 1, 0)
                    ))
                }
                self.linkHref = nil
                linkText = ""
            }
            return
        }
        guard tocDepth > 0 else { return }
        if name == "ol" {
            listDepth = max(listDepth - 1, 0)
        } else if name == "nav" {
            tocDepth -= 1
            if tocDepth == 0 {
                listDepth = 0
            }
        }
    }
}

private final class NCXNavigationParser: NSObject, XMLParserDelegate {
    private struct Context {
        var title = ""
        var href: String?
        var emitted = false
    }

    private var entries: [EPUBNavigationEntry] = []
    private var contexts: [Context] = []
    private var ignoredNavPointDepth = 0
    private var navLabelDepth = 0
    private var capturesLabelText = false
    private var labelText = ""

    static func parse(_ data: Data) -> [EPUBNavigationEntry]? {
        let delegate = NCXNavigationParser()
        let parser = XMLParser(data: XHTMLTextParser.sanitize(data))
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        if name == "navpoint", ignoredNavPointDepth > 0 {
            ignoredNavPointDepth += 1
            return
        }
        if ignoredNavPointDepth > 0 { return }

        switch name {
        case "navpoint":
            if contexts.count < 100 {
                contexts.append(Context())
            } else {
                ignoredNavPointDepth = 1
            }
        case "navlabel" where !contexts.isEmpty:
            navLabelDepth += 1
        case "text" where !contexts.isEmpty && navLabelDepth > 0:
            capturesLabelText = true
            labelText = ""
        case "content" where !contexts.isEmpty:
            contexts[contexts.count - 1].href = attributeDict["src"]
            emitCurrentIfReady()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard ignoredNavPointDepth == 0, capturesLabelText else { return }
        labelText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        if ignoredNavPointDepth > 0 {
            if name == "navpoint" {
                ignoredNavPointDepth -= 1
            }
            return
        }

        switch name {
        case "text" where capturesLabelText && !contexts.isEmpty:
            contexts[contexts.count - 1].title = BookTextProcessor.normalize(labelText)
            capturesLabelText = false
            labelText = ""
            emitCurrentIfReady()
        case "navlabel" where navLabelDepth > 0:
            navLabelDepth -= 1
        case "navpoint" where !contexts.isEmpty:
            emitCurrentIfReady()
            contexts.removeLast()
            navLabelDepth = min(navLabelDepth, contexts.count)
        default:
            break
        }
    }

    private func emitCurrentIfReady() {
        guard !contexts.isEmpty,
              !contexts[contexts.count - 1].emitted,
              !contexts[contexts.count - 1].title.isEmpty,
              let href = contexts[contexts.count - 1].href,
              !href.isEmpty,
              entries.count < 20_000 else {
            return
        }
        contexts[contexts.count - 1].emitted = true
        entries.append(.init(
            title: contexts[contexts.count - 1].title,
            href: href,
            level: max(contexts.count - 1, 0)
        ))
    }
}

private struct ParsedXHTML {
    struct Heading {
        let title: String
        let blockIndex: Int
        let level: Int
    }

    let blocks: [String]
    let firstHeading: String?
    let anchorBlockIndices: [String: Int]
    let headings: [Heading]
}

private final class XHTMLTextParser: NSObject, XMLParserDelegate {
    private static let blockElements: Set<String> = [
        "p", "div", "section", "article", "li", "blockquote",
        "h1", "h2", "h3", "h4", "h5", "h6", "dt", "dd", "pre"
    ]
    private static let ignoredElements: Set<String> = [
        "head", "script", "style", "svg", "math"
    ]

    private var blocks: [String] = []
    private var current = ""
    private var ignoredDepth = 0
    private var headingDepth = 0
    private var headingText = ""
    private var activeHeadingLevel = 1
    private var firstHeading: String?
    private var anchorBlockIndices: [String: Int] = [:]
    private var headings: [ParsedXHTML.Heading] = []

    static func parse(_ data: Data) -> ParsedXHTML? {
        let sanitized = sanitize(data)
        let delegate = XHTMLTextParser()
        let parser = XMLParser(data: sanitized)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        delegate.flush()
        return ParsedXHTML(
            blocks: delegate.blocks,
            firstHeading: delegate.firstHeading,
            anchorBlockIndices: delegate.anchorBlockIndices,
            headings: delegate.headings
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        if ignoredDepth > 0 {
            ignoredDepth += 1
            return
        }
        if Self.ignoredElements.contains(name) {
            flush()
            ignoredDepth = 1
            return
        }
        if Self.blockElements.contains(name) {
            flush()
        }
        if let anchor = attributeDict["id"] ?? attributeDict["xml:id"],
           !anchor.isEmpty,
           anchorBlockIndices.count < 100_000,
           anchorBlockIndices[anchor] == nil {
            anchorBlockIndices[anchor] = blocks.count
        }
        if let level = Self.headingLevel(for: name) {
            headingDepth += 1
            if headingDepth == 1 {
                headingText = ""
                activeHeadingLevel = level
            }
        }
        if name == "br" {
            current += " "
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard ignoredDepth == 0 else { return }
        current += string
        if headingDepth > 0 {
            headingText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if ignoredDepth > 0 {
            ignoredDepth -= 1
            return
        }
        let name = localName(elementName)
        if Self.headingLevel(for: name) != nil, headingDepth > 0 {
            if headingDepth == 1 {
                let normalized = BookTextProcessor.normalize(headingText)
                if firstHeading == nil, !normalized.isEmpty {
                    firstHeading = normalized
                }
                if !normalized.isEmpty, headings.count < 20_000 {
                    headings.append(.init(
                        title: normalized,
                        blockIndex: blocks.count,
                        level: min(max(activeHeadingLevel - 1, 0), 3)
                    ))
                }
            }
            headingDepth -= 1
        }
        if Self.blockElements.contains(name) {
            flush()
        }
    }

    private func flush() {
        let normalized = BookTextProcessor.normalize(current)
        if !normalized.isEmpty {
            blocks.append(normalized)
        }
        current = ""
    }

    private static func headingLevel(for name: String) -> Int? {
        guard name.count == 2,
              name.first == "h",
              let level = name.last?.wholeNumberValue,
              (1...6).contains(level) else {
            return nil
        }
        return level
    }

    fileprivate static func sanitize(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        let replacements = [
            "&nbsp;": "&#160;",
            "&iexcl;": "&#161;",
            "&cent;": "&#162;",
            "&pound;": "&#163;",
            "&curren;": "&#164;",
            "&yen;": "&#165;",
            "&brvbar;": "&#166;",
            "&sect;": "&#167;",
            "&uml;": "&#168;",
            "&copy;": "&#169;",
            "&ordf;": "&#170;",
            "&laquo;": "&#171;",
            "&not;": "&#172;",
            "&shy;": "&#173;",
            "&reg;": "&#174;",
            "&macr;": "&#175;",
            "&deg;": "&#176;",
            "&plusmn;": "&#177;",
            "&sup2;": "&#178;",
            "&sup3;": "&#179;",
            "&acute;": "&#180;",
            "&micro;": "&#181;",
            "&para;": "&#182;",
            "&middot;": "&#183;",
            "&cedil;": "&#184;",
            "&sup1;": "&#185;",
            "&ordm;": "&#186;",
            "&raquo;": "&#187;",
            "&frac14;": "&#188;",
            "&frac12;": "&#189;",
            "&frac34;": "&#190;",
            "&iquest;": "&#191;",
            "&Agrave;": "&#192;",
            "&Aacute;": "&#193;",
            "&Acirc;": "&#194;",
            "&Atilde;": "&#195;",
            "&Auml;": "&#196;",
            "&Aring;": "&#197;",
            "&AElig;": "&#198;",
            "&Ccedil;": "&#199;",
            "&Egrave;": "&#200;",
            "&Eacute;": "&#201;",
            "&Ecirc;": "&#202;",
            "&Euml;": "&#203;",
            "&Igrave;": "&#204;",
            "&Iacute;": "&#205;",
            "&Icirc;": "&#206;",
            "&Iuml;": "&#207;",
            "&ETH;": "&#208;",
            "&Ntilde;": "&#209;",
            "&Ograve;": "&#210;",
            "&Oacute;": "&#211;",
            "&Ocirc;": "&#212;",
            "&Otilde;": "&#213;",
            "&Ouml;": "&#214;",
            "&times;": "&#215;",
            "&Oslash;": "&#216;",
            "&Ugrave;": "&#217;",
            "&Uacute;": "&#218;",
            "&Ucirc;": "&#219;",
            "&Uuml;": "&#220;",
            "&Yacute;": "&#221;",
            "&THORN;": "&#222;",
            "&szlig;": "&#223;",
            "&agrave;": "&#224;",
            "&aacute;": "&#225;",
            "&acirc;": "&#226;",
            "&atilde;": "&#227;",
            "&auml;": "&#228;",
            "&aring;": "&#229;",
            "&aelig;": "&#230;",
            "&ccedil;": "&#231;",
            "&egrave;": "&#232;",
            "&eacute;": "&#233;",
            "&ecirc;": "&#234;",
            "&euml;": "&#235;",
            "&igrave;": "&#236;",
            "&iacute;": "&#237;",
            "&icirc;": "&#238;",
            "&iuml;": "&#239;",
            "&eth;": "&#240;",
            "&ntilde;": "&#241;",
            "&ograve;": "&#242;",
            "&oacute;": "&#243;",
            "&ocirc;": "&#244;",
            "&otilde;": "&#245;",
            "&ouml;": "&#246;",
            "&divide;": "&#247;",
            "&oslash;": "&#248;",
            "&ugrave;": "&#249;",
            "&uacute;": "&#250;",
            "&ucirc;": "&#251;",
            "&uuml;": "&#252;",
            "&yacute;": "&#253;",
            "&thorn;": "&#254;",
            "&yuml;": "&#255;",
            "&OElig;": "&#338;",
            "&oelig;": "&#339;",
            "&Scaron;": "&#352;",
            "&scaron;": "&#353;",
            "&Yuml;": "&#376;",
            "&fnof;": "&#402;",
            "&circ;": "&#710;",
            "&tilde;": "&#732;",
            "&ensp;": "&#8194;",
            "&emsp;": "&#8195;",
            "&thinsp;": "&#8201;",
            "&zwnj;": "&#8204;",
            "&zwj;": "&#8205;",
            "&lrm;": "&#8206;",
            "&rlm;": "&#8207;",
            "&mdash;": "&#8212;",
            "&ndash;": "&#8211;",
            "&hellip;": "&#8230;",
            "&lsquo;": "&#8216;",
            "&rsquo;": "&#8217;",
            "&ldquo;": "&#8220;",
            "&rdquo;": "&#8221;",
            "&sbquo;": "&#8218;",
            "&bdquo;": "&#8222;",
            "&dagger;": "&#8224;",
            "&Dagger;": "&#8225;",
            "&permil;": "&#8240;",
            "&lsaquo;": "&#8249;",
            "&rsaquo;": "&#8250;",
            "&euro;": "&#8364;",
            "&trade;": "&#8482;"
        ]
        for (entity, replacement) in replacements {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return Data(text.utf8)
    }
}

private func localName(_ qualifiedName: String) -> String {
    qualifiedName.split(separator: ":").last.map(String.init)?.lowercased()
        ?? qualifiedName.lowercased()
}

private extension Data {
    func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw ArchiveReadError.outOfBounds }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw ArchiveReadError.outOfBounds }
        return UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }
}
