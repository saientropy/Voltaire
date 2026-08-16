import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack(path: $appModel.path) {
            LibraryView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case let .reader(documentID):
                        if let document = appModel.document(id: documentID) {
                            ReaderView(
                                document: document,
                                initialPosition: appModel.position(for: document),
                                initialLinePreset: appModel.linePreset(for: document.id),
                                initialAppearance: appModel.readerAppearance(),
                                onPositionChange: { position in
                                    appModel.savePosition(position, for: document.id)
                                },
                                onLinePresetChange: { preset in
                                    appModel.saveLinePreset(preset, for: document.id)
                                },
                                onAppearanceChange: { appearance in
                                    appModel.saveReaderAppearance(appearance)
                                }
                            )
                        } else {
                            ContentUnavailableView(
                                "Book unavailable",
                                systemImage: "books.vertical"
                            )
                        }
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .tint(ReadingTokens.ink)
        .background {
            ReadingTokens.canvas
                .ignoresSafeArea()
        }
        .task {
            await appModel.loadLibrary()
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--reader-appearance-showcase") {
                appModel.saveReaderAppearance(ReaderAppearance(
                    textSize: .extraLarge,
                    lineSpacing: .relaxed,
                    margin: .wide
                ))
            }
            if arguments.contains("--open-sample"),
               appModel.path.isEmpty {
                appModel.openSample()
            }
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isImporterPresented = false
    @AccessibilityFocusState private var importStatusFocused: Bool

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 24)]
        }
        return [GridItem(.adaptive(minimum: 280, maximum: 520), spacing: 24)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VoltaireMarkView()

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        libraryIntroduction
                        Spacer(minLength: 8)
                        importButton
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        libraryIntroduction
                        importButton
                    }
                }

                statusMessages

                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(appModel.documents) { document in
                        NavigationLink(value: AppRoute.reader(documentID: document.id)) {
                            LibraryBookCard(
                                document: document,
                                progressLabel: appModel.progressLabel(for: document)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(document.title), \(document.author), \(document.libraryStructureLabel), \(appModel.progressLabel(for: document))")
                        .accessibilityHint("Opens the book.")
                        .accessibilityIdentifier("library-book-\(document.id)")
                    }
                }

            }
            .frame(maxWidth: ReadingTokens.libraryMaxWidth, alignment: .leading)
            .padding(.horizontal, ReadingTokens.libraryPadding)
            .padding(.top, 40)
            .padding(.bottom, 64)
        }
        .background {
            ReadingTokens.canvas
                .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-screen")
        .onChange(of: appModel.importMessage) { _, message in
            importStatusFocused = message != nil
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.epub, .pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task {
                    await appModel.importBook(from: url)
                }
            case let .failure(error):
                if (error as? CocoaError)?.code != .userCancelled {
                    appModel.reportFilePickerFailure()
                }
            }
        }
    }

    private var libraryIntroduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your library")
                .font(.system(.title, design: .serif, weight: .semibold))
                .foregroundStyle(ReadingTokens.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Books stay on this iPad. Open one and keep reading from where you left off.")
                .font(.body)
                .foregroundStyle(ReadingTokens.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var importButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            HStack(spacing: 9) {
                if appModel.isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
                Text(appModel.isImporting ? "Importing…" : "Import book")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ReadingTokens.canvas)
            .padding(.horizontal, 18)
            .frame(minHeight: ReadingTokens.touchTarget)
            .background(ReadingTokens.ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(appModel.isImporting)
        .accessibilityHint("Choose a DRM-free EPUB or a text-based PDF.")
        .accessibilityIdentifier("library-import-button")
    }

    @ViewBuilder
    private var statusMessages: some View {
        if appModel.isLoadingLibrary {
            ProgressView("Loading your library…")
                .tint(ReadingTokens.ink)
                .foregroundStyle(ReadingTokens.secondaryInk)
        }

        if let message = appModel.libraryMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(ReadingTokens.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let message = appModel.importMessage {
            Label(
                message,
                systemImage: appModel.importFailed
                    ? "exclamationmark.triangle"
                    : "checkmark.circle"
            )
            .font(.callout)
            .foregroundStyle(ReadingTokens.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityFocused($importStatusFocused)
            .accessibilityIdentifier("library-import-message")
        }
    }
}

private struct VoltaireMarkView: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("V")
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .frame(width: 52, height: 52)
                .foregroundStyle(ReadingTokens.canvas)
                .background(ReadingTokens.ink, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text("VOLTAIRE")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(ReadingTokens.ink)
                Text("A quiet place to read")
                    .font(.caption)
                    .foregroundStyle(ReadingTokens.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voltaire. A quiet place to read.")
    }
}

private struct LibraryBookCard: View {
    let document: ReaderDocument
    let progressLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            BookCover(document: document)

            VStack(alignment: .leading, spacing: 8) {
                Text(document.title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(ReadingTokens.ink)
                    .lineLimit(2)
                Text(document.author)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ReadingTokens.secondaryInk)
                Divider()
                    .overlay(ReadingTokens.hairline)
                Text(document.libraryStructureLabel)
                    .font(.caption.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(ReadingTokens.secondaryInk)
                Text(progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReadingTokens.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 184, alignment: .leading)
        .background(
            ReadingTokens.controlSurface,
            in: RoundedRectangle(cornerRadius: ReadingTokens.cardCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ReadingTokens.cardCornerRadius)
                .stroke(ReadingTokens.hairline, lineWidth: 1)
        }
        .shadow(color: ReadingTokens.ink.opacity(0.08), radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: ReadingTokens.cardCornerRadius))
    }
}

private struct BookCover: View {
    let document: ReaderDocument

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(ReadingTokens.ink)
            VStack(spacing: 10) {
                Text("V")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                Rectangle()
                    .frame(width: 38, height: 1)
                Text(document.title.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .tracking(1.4)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .foregroundStyle(ReadingTokens.canvas)
            .padding(10)
        }
        .frame(width: 104, height: 148)
        .shadow(color: ReadingTokens.ink.opacity(0.16), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}
