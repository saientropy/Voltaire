import CoreText
import Foundation
import UIKit

struct SentenceLayoutEngine {
    enum LinePreset: Hashable, CaseIterable, Identifiable, Sendable {
        case lines(Int)
        case fullPage

        static let allCases: [LinePreset] = (3...20).map(LinePreset.lines) + [.fullPage]

        var id: String {
            switch self {
            case .lines(let count): "lines-\(count)"
            case .fullPage: "full-page"
            }
        }

        var label: String {
            switch self {
            case .lines(let count): "\(count) lines"
            case .fullPage: "Full page"
            }
        }

        var lineCount: Int? {
            switch self {
            case .lines(let count): count
            case .fullPage: nil
            }
        }

        init?(persistedID: String) {
            if persistedID == "full-page" {
                self = .fullPage
                return
            }
            guard persistedID.hasPrefix("lines-"),
                  let count = Int(persistedID.dropFirst("lines-".count)),
                  (3...20).contains(count) else {
                return nil
            }
            self = .lines(count)
        }
    }

    func makeWindow(
        document: ReaderDocument,
        position: ReaderPosition,
        width: Double,
        fontSize: Double,
        preset: LinePreset
    ) -> ReaderWindow {
        makeWindow(
            lines: makeLines(document: document, width: width, fontSize: fontSize),
            position: position,
            preset: preset
        )
    }

    func makeWindow(
        lines allLines: [ReaderLine],
        position: ReaderPosition,
        preset: LinePreset
    ) -> ReaderWindow {
        guard !allLines.isEmpty else {
            return ReaderWindow(
                lines: [],
                anchoredSentenceID: position.sentenceID,
                anchorLineID: "",
                requestedLineCount: preset.lineCount
            )
        }
        let sentenceStart = allLines.firstIndex { $0.sentenceID == position.sentenceID } ?? 0
        let sentenceLines = allLines.filter { $0.sentenceID == position.sentenceID }
        let anchorIndex = min(sentenceStart + max(position.rowOffset, 0), sentenceStart + max(sentenceLines.count - 1, 0))

        guard let lineCount = preset.lineCount else {
            return ReaderWindow(
                lines: allLines,
                anchoredSentenceID: position.sentenceID,
                anchorLineID: allLines[anchorIndex].id,
                requestedLineCount: nil
            )
        }

        let start = anchorIndex
        let end = min(allLines.count, start + lineCount)
        let lines = Array(allLines[start..<end])

        return ReaderWindow(
            lines: lines,
            anchoredSentenceID: position.sentenceID,
            anchorLineID: lines.first?.id ?? allLines[anchorIndex].id,
            requestedLineCount: lineCount
        )
    }

    func makeLines(document: ReaderDocument, width: Double, fontSize: Double) -> [ReaderLine] {
        return document.sentences.flatMap { sentence in
            makeLines(sentence: sentence, width: width, fontSize: fontSize)
        }
    }

    func makeLines(sentence: ReaderSentence, width: Double, fontSize: Double) -> [ReaderLine] {
        let words = wordsWithRanges(in: sentence.text)
        guard !words.isEmpty else { return [] }

        let layout = normalizedLayoutText(from: words)
        let baseFont = UIFont.systemFont(ofSize: max(CGFloat(fontSize), 1))
        let serifDescriptor = baseFont.fontDescriptor.withDesign(.serif)
            ?? baseFont.fontDescriptor
        let font = UIFont(descriptor: serifDescriptor, size: baseFont.pointSize)
        let attributed = NSAttributedString(
            string: layout.text,
            attributes: [.font: font]
        )
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let text = layout.text as NSString
        var result: [ReaderLine] = []
        var offset = 0

        while offset < text.length {
            let suggested = CTTypesetterSuggestLineBreak(
                typesetter,
                offset,
                max(CGFloat(width), 1)
            )
            let count = max(suggested, 1)
            let rawRange = NSRange(
                location: offset,
                length: min(count, text.length - offset)
            )
            offset = NSMaxRange(rawRange)

            guard let displayRange = trimmedRange(rawRange, in: text),
                  let sourceRange = sourceRange(
                      for: displayRange,
                      tokens: layout.tokens
                  ) else {
                continue
            }
            let lineNumber = result.count
            result.append(ReaderLine(
                id: "\(sentence.id)-\(lineNumber)",
                sentenceID: sentence.id,
                text: text.substring(with: displayRange),
                sourceRange: sourceRange,
                isFirstLineOfSentence: lineNumber == 0
            ))
        }

        return result
    }

    private struct LayoutToken {
        let displayRange: NSRange
        let sourceRange: NSRange
    }

    private func normalizedLayoutText(
        from words: [(String, NSRange)]
    ) -> (text: String, tokens: [LayoutToken]) {
        var text = ""
        var tokens: [LayoutToken] = []
        for (index, item) in words.enumerated() {
            if index > 0 {
                text.append(" ")
            }
            let location = text.utf16.count
            text.append(item.0)
            tokens.append(LayoutToken(
                displayRange: NSRange(location: location, length: item.0.utf16.count),
                sourceRange: item.1
            ))
        }
        return (text, tokens)
    }

    private func trimmedRange(_ range: NSRange, in text: NSString) -> NSRange? {
        let substring = text.substring(with: range) as NSString
        let first = substring.rangeOfCharacter(from: .whitespacesAndNewlines.inverted)
        guard first.location != NSNotFound else { return nil }
        let last = substring.rangeOfCharacter(
            from: .whitespacesAndNewlines.inverted,
            options: .backwards
        )
        return NSRange(
            location: range.location + first.location,
            length: NSMaxRange(last) - first.location
        )
    }

    private func sourceRange(
        for displayRange: NSRange,
        tokens: [LayoutToken]
    ) -> NSRange? {
        let intersecting = tokens.filter {
            NSIntersectionRange($0.displayRange, displayRange).length > 0
        }
        guard let first = intersecting.first, let last = intersecting.last else {
            return nil
        }

        let firstDisplayOffset = max(displayRange.location, first.displayRange.location)
            - first.displayRange.location
        let lastDisplayEnd = min(NSMaxRange(displayRange), NSMaxRange(last.displayRange))
            - last.displayRange.location
        let sourceStart = first.sourceRange.location + firstDisplayOffset
        let sourceEnd = last.sourceRange.location + lastDisplayEnd
        return NSRange(location: sourceStart, length: max(sourceEnd - sourceStart, 0))
    }

    private func wordsWithRanges(in text: String) -> [(String, NSRange)] {
        var words: [(String, NSRange)] = []
        var start: String.Index?

        for index in text.indices {
            if text[index].isWhitespace {
                if let start {
                    words.append((
                        String(text[start..<index]),
                        NSRange(start..<index, in: text)
                    ))
                }
                start = nil
            } else if start == nil {
                start = index
            }
        }

        if let start {
            words.append((
                String(text[start...]),
                NSRange(start..<text.endIndex, in: text)
            ))
        }
        return words
    }

}
