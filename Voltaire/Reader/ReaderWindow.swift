import Foundation

struct ReaderLine: Equatable, Identifiable {
    let id: String
    let sentenceID: String
    let text: String
    let sourceRange: NSRange
    let isFirstLineOfSentence: Bool

    func displayRange(for spokenRange: NSRange, in originalText: String) -> NSRange? {
        let intersection = NSIntersectionRange(sourceRange, spokenRange)
        guard intersection.length > 0 else { return nil }

        let original = originalText as NSString
        let lineText = original.substring(with: sourceRange)
        var display = ""
        var displayStart: Int?
        var displayEnd: Int?
        var previousWasWhitespace = false
        var offset = 0

        for character in lineText {
            let characterLength = String(character).utf16.count
            let sourceStart = sourceRange.location + offset
            let overlapsSpoken = NSIntersectionRange(
                NSRange(location: sourceStart, length: characterLength),
                intersection
            ).length > 0

            if character.isWhitespace {
                if !display.isEmpty && !previousWasWhitespace {
                    if overlapsSpoken {
                        displayStart = displayStart ?? display.utf16.count
                        displayEnd = display.utf16.count + 1
                    }
                    display.append(" ")
                }
                previousWasWhitespace = true
            } else {
                let start = display.utf16.count
                display.append(character)
                if overlapsSpoken {
                    displayStart = displayStart ?? start
                    displayEnd = display.utf16.count
                }
                previousWasWhitespace = false
            }
            offset += characterLength
        }

        guard let displayStart, let displayEnd, displayEnd > displayStart else {
            return nil
        }
        return NSRange(location: displayStart, length: displayEnd - displayStart)
    }
}

struct ReaderWindow: Equatable {
    let lines: [ReaderLine]
    let anchoredSentenceID: String
    let anchorLineID: String
    let requestedLineCount: Int?
}
