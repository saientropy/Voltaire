import CoreText
import Foundation
import Testing
import UIKit
@testable import Voltaire

struct SentenceLayoutEngineTests {
    let engine = SentenceLayoutEngine()

    @Test func presetKeepsCurrentSentenceVisible() {
        let document = SampleChapter.document
        let position = ReaderPosition(sentenceID: "candide-009")
        let window = engine.makeWindow(
            document: document,
            position: position,
            width: 420,
            fontSize: 20,
            preset: .lines(3)
        )

        #expect(window.anchoredSentenceID == position.sentenceID)
        #expect(window.lines.contains { $0.sentenceID == position.sentenceID })
        #expect(window.lines.count == 3)
    }

    @Test func fullPageContainsTheWholeSample() {
        let document = SampleChapter.document
        let window = engine.makeWindow(
            document: document,
            position: ReaderPosition(sentenceID: "candide-004"),
            width: 700,
            fontSize: 20,
            preset: .fullPage
        )

        #expect(window.lines.count > 18)
        #expect(window.lines.contains { $0.sentenceID == "candide-004" })
        #expect(window.requestedLineCount == nil)
    }

    @Test func widthChangesRecalculateAroundTheSameSentence() {
        let document = SampleChapter.document
        let position = ReaderPosition(sentenceID: "candide-007")
        let narrow = engine.makeWindow(document: document, position: position, width: 300, fontSize: 20, preset: .lines(12))
        let wide = engine.makeWindow(document: document, position: position, width: 700, fontSize: 20, preset: .lines(12))

        #expect(narrow.anchoredSentenceID == wide.anchoredSentenceID)
        #expect(narrow.lines.contains { $0.sentenceID == position.sentenceID })
        #expect(wide.lines.contains { $0.sentenceID == position.sentenceID })
    }

    @Test func longSentenceCannotBeClippedOutBySmallPreset() {
        let document = ReaderDocument(
            id: "long",
            title: "Test",
            author: "Test",
            chapterTitle: "Test",
            sentences: [ReaderSentence(id: "long-001", text: String(repeating: "long word ", count: 80))]
        )
        let window = engine.makeWindow(
            document: document,
            position: ReaderPosition(sentenceID: "long-001"),
            width: 240,
            fontSize: 20,
            preset: .lines(3)
        )

        #expect(window.lines.count == 3)
        #expect(window.lines.allSatisfy { $0.sentenceID == "long-001" })
    }

    @Test func exposesEveryExactLineCountAndFullPage() {
        #expect(SentenceLayoutEngine.LinePreset.allCases.count == 19)
        #expect(SentenceLayoutEngine.LinePreset.allCases.first?.label == "3 lines")
        #expect(SentenceLayoutEngine.LinePreset.allCases.dropLast().last?.label == "20 lines")
        #expect(SentenceLayoutEngine.LinePreset.allCases.last?.label == "Full page")
    }

    @Test func preservesExactOriginalUTF16RangesForNormalizedWhitespace() {
        let document = ReaderDocument(
            id: "ranges",
            title: "Ranges",
            author: "Test",
            chapterTitle: "Test",
            sentences: [ReaderSentence(id: "repeat", text: "one  two one  two one  two")]
        )
        let lines = engine.makeLines(document: document, width: 124, fontSize: 20)
        let original = document.sentences[0].text as NSString

        #expect(lines.map(\.text) == ["one two one", "two one two"])
        #expect(original.substring(with: lines[0].sourceRange) == "one  two one")
        #expect(original.substring(with: lines[1].sourceRange) == "two one  two")
        #expect(lines[0].sourceRange.location == 0)
        #expect(lines[1].sourceRange.location > NSMaxRange(lines[0].sourceRange))
    }

    @Test func highlightsRepeatedFragmentUsingItsOriginalRange() {
        let document = ReaderDocument(
            id: "repeated",
            title: "Repeated",
            author: "Test",
            chapterTitle: "Test",
            sentences: [ReaderSentence(id: "repeat", text: "one  two one  two one  two")]
        )
        let lines = engine.makeLines(document: document, width: 124, fontSize: 20)
        let secondSpokenRange = NSRange(location: 14, length: 7)

        #expect(lines[0].displayRange(for: secondSpokenRange, in: document.sentences[0].text) == nil)
        #expect(lines[1].displayRange(for: secondSpokenRange, in: document.sentences[0].text) == NSRange(location: 0, length: 7))
    }

    @Test func measuredLinesFitTheExactRenderedSerifWidth() {
        let sentence = ReaderSentence(
            id: "metrics-1",
            text: "A narrow iPad column must never wrap one calculated row into two visible rows."
        )
        let width = 180.0
        let fontSize = 28.0
        let lines = engine.makeLines(sentence: sentence, width: width, fontSize: fontSize)
        let baseFont = UIFont.systemFont(ofSize: fontSize)
        let descriptor = baseFont.fontDescriptor.withDesign(.serif) ?? baseFont.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: fontSize)

        #expect(lines.count > 1)
        for line in lines {
            let attributed = NSAttributedString(
                string: line.text,
                attributes: [.font: font]
            )
            let measured = CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(attributed),
                nil,
                nil,
                nil
            )
            #expect(measured <= width + 0.5)
        }
    }
}
