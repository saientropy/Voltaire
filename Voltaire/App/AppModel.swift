import Foundation
import Observation

enum AppRoute: Hashable {
    case reader(documentID: String)
}

@Observable
final class AppModel {
    var documents: [ReaderDocument]
    var path: [AppRoute] = []
    var isLoadingLibrary = false
    var libraryMessage: String?
    var isImporting = false
    var importMessage: String?
    var importFailed = false
    private(set) var savedPositions: [String: ReaderPosition] = [:]

    @ObservationIgnored private let repository: LibraryRepository
    @ObservationIgnored private let importer: BookImportCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let bundledDocuments: [ReaderDocument]
    @ObservationIgnored private var hasLoadedLibrary = false

    init(
        documents: [ReaderDocument] = [SampleChapter.document],
        repository: LibraryRepository = LibraryRepository(),
        importer: BookImportCoordinator? = nil,
        defaults: UserDefaults = .standard
    ) {
        let readableDocuments = documents.filter(Self.isReadable)
        let bundled = readableDocuments.isEmpty ? [SampleChapter.document] : readableDocuments
        self.documents = bundled
        self.bundledDocuments = bundled
        self.repository = repository
        self.importer = importer ?? BookImportCoordinator(repository: repository)
        self.defaults = defaults
    }

    var sampleDocument: ReaderDocument {
        documents.first ?? SampleChapter.document
    }

    func document(id: String) -> ReaderDocument? {
        documents.first { $0.id == id }
    }

    func open(documentID: String) {
        guard document(id: documentID) != nil else { return }
        path.append(.reader(documentID: documentID))
    }

    func openSample() {
        open(documentID: sampleDocument.id)
    }

    func closeReader() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    @MainActor
    func loadLibrary() async {
        guard !hasLoadedLibrary else { return }
        hasLoadedLibrary = true
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }

        do {
            let imported = try await repository.loadDocuments()
            let bundledIDs = Set(bundledDocuments.map(\.id))
            documents = bundledDocuments + imported.filter { !bundledIDs.contains($0.id) }
            libraryMessage = nil
        } catch {
            documents = bundledDocuments
            libraryMessage = "Your imported books could not be loaded. The bundled sample is still available."
        }
    }

    func position(for document: ReaderDocument) -> ReaderPosition {
        let fallback = ReaderPosition(sentenceID: document.sentences.first?.id ?? "")
        if let saved = savedPositions[document.id],
           document.sentences.contains(where: { $0.id == saved.sentenceID }) {
            return saved
        }
        guard let data = defaults.data(forKey: positionKey(document.id)),
              let saved = try? JSONDecoder().decode(ReaderPosition.self, from: data),
              document.sentences.contains(where: { $0.id == saved.sentenceID }) else {
            return fallback
        }
        return saved
    }

    func savePosition(_ position: ReaderPosition, for documentID: String) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        defaults.set(data, forKey: positionKey(documentID))
        if savedPositions[documentID] != position {
            savedPositions[documentID] = position
        }
    }

    func progressLabel(for document: ReaderDocument) -> String {
        let saved = position(for: document)
        guard let index = document.sentences.firstIndex(where: { $0.id == saved.sentenceID }) else {
            return "New"
        }
        if index == 0, saved.rowOffset == 0 {
            return "New"
        }
        let percent = min(
            100,
            max(1, Int((Double(index + 1) / Double(max(document.sentences.count, 1)) * 100).rounded()))
        )
        return percent == 100 ? "Finished" : "\(percent)% read"
    }

    func linePreset(for documentID: String) -> SentenceLayoutEngine.LinePreset {
        guard let id = defaults.string(forKey: linePresetKey(documentID)),
              let preset = SentenceLayoutEngine.LinePreset(persistedID: id) else {
            return .fullPage
        }
        return preset
    }

    func saveLinePreset(
        _ preset: SentenceLayoutEngine.LinePreset,
        for documentID: String
    ) {
        defaults.set(preset.id, forKey: linePresetKey(documentID))
    }

    func readerAppearance() -> ReaderAppearance {
        guard let data = defaults.data(forKey: readerAppearanceKey),
              let appearance = try? JSONDecoder().decode(ReaderAppearance.self, from: data) else {
            return .bookDefault
        }
        return appearance
    }

    func saveReaderAppearance(_ appearance: ReaderAppearance) {
        guard let data = try? JSONEncoder().encode(appearance) else { return }
        defaults.set(data, forKey: readerAppearanceKey)
    }

    @MainActor
    func importBook(from url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        importMessage = nil
        importFailed = false
        defer { isImporting = false }

        do {
            let document = try await importer.importBook(from: url)
            if !documents.contains(where: { $0.id == document.id }) {
                documents.append(document)
            }
            importMessage = "Added \(document.title) to your library."
        } catch let error as BookImportError {
            importFailed = true
            importMessage = error.localizedDescription
        } catch {
            importFailed = true
            importMessage = "That book could not be imported. Try another file."
        }
    }

    @MainActor
    func reportFilePickerFailure() {
        importFailed = true
        importMessage = "Voltaire could not open the file picker result. Try again."
    }

    private func positionKey(_ documentID: String) -> String {
        "reader.position.\(documentID)"
    }

    private func linePresetKey(_ documentID: String) -> String {
        "reader.line-preset.\(documentID)"
    }

    private var readerAppearanceKey: String {
        "reader.appearance"
    }

    private static func isReadable(_ document: ReaderDocument) -> Bool {
        !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !document.sentences.isEmpty &&
        document.sentences.allSatisfy {
            !$0.id.isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } &&
        Set(document.sentences.map(\.id)).count == document.sentences.count
    }
}
