import Foundation

/// Packs pages of text into chunks small enough for the on-device model's input limit.
/// Whole pages stay together where they fit, so an exercise isn't split from its dosage;
/// a page too long on its own is split between lines.
enum PageChunker {
    static func chunks(_ pages: [[String]], maxCharacters: Int) -> [[String]] {
        var chunks: [[String]] = []
        var current: [String] = []
        var currentSize = 0

        func flush() {
            if !current.isEmpty { chunks.append(current) }
            current = []
            currentSize = 0
        }

        for page in pages where !page.isEmpty {
            let pageSize = size(of: page)
            if pageSize <= maxCharacters {
                if currentSize + pageSize > maxCharacters { flush() }
                current += page
                currentSize += pageSize
                continue
            }
            // Too long for one chunk: start fresh and split between lines.
            flush()
            for line in page {
                let lineSize = line.count + 1
                if currentSize + lineSize > maxCharacters { flush() }
                current.append(line)
                currentSize += lineSize
            }
            flush()
        }
        flush()
        return chunks
    }

    /// Characters including one newline per line, as the lines are joined for the model.
    static func size(of lines: [String]) -> Int {
        lines.reduce(0) { $0 + $1.count + 1 }
    }
}
