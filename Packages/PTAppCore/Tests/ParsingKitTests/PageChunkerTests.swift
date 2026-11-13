import XCTest
@testable import ParsingKit

final class PageChunkerTests: XCTestCase {
    func test_pagesThatFit_stayTogetherInOneChunk() {
        let chunks = PageChunker.chunks([["Bridges 3x10"], ["Clams 2x15"]], maxCharacters: 100)
        XCTAssertEqual(chunks, [["Bridges 3x10", "Clams 2x15"]])
    }

    func test_pagesThatDontFitTogether_startANewChunk_withoutSplittingAPage() {
        let page1 = ["Bridges", "3 sets of 10"]      // 8 + 13 = 21
        let page2 = ["Clamshells", "2 sets of 15"]   // 11 + 13 = 24
        let chunks = PageChunker.chunks([page1, page2], maxCharacters: 30)
        XCTAssertEqual(chunks, [page1, page2])
    }

    func test_aPageTooLongOnItsOwn_isSplitBetweenLines() {
        let page = (1...6).map { "Exercise \($0) 3x10" }   // 18 + 1 each
        let chunks = PageChunker.chunks([page], maxCharacters: 40)
        XCTAssertEqual(chunks.flatMap { $0 }, page)
        XCTAssertTrue(chunks.allSatisfy { PageChunker.size(of: $0) <= 40 })
        XCTAssertEqual(chunks.count, 3)
    }

    func test_aLongPage_doesntShareAChunkWithItsNeighbours() {
        let long = (1...6).map { "Exercise \($0) 3x10" }
        let chunks = PageChunker.chunks([["Warm up"], long, ["Cool down"]], maxCharacters: 40)
        XCTAssertEqual(chunks.first, ["Warm up"])
        XCTAssertEqual(chunks.last, ["Cool down"])
    }

    func test_emptyPages_areDropped() {
        XCTAssertEqual(PageChunker.chunks([[], ["Bridges"], []], maxCharacters: 100), [["Bridges"]])
        XCTAssertEqual(PageChunker.chunks([], maxCharacters: 100), [])
    }
}
