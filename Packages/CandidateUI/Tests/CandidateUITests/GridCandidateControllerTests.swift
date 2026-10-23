import Cocoa
import Testing

@testable import CandidateUI

@MainActor
@Suite("Test the Grid Candidate Controller")
final class GridCandidateControllerTests {

    class Mock: CandidateControllerDelegate {
        let candidates = [
            "A", "B", "C", "D", "E",
            "F", "G", "H", "I", "J",
            "K", "L", "M", "N", "O",
            "P", "Q", "R", "S", "T",
            "U", "V", "W", "X", "Y"
        ]
        var selected: String?

        func candidateCountForController(_ controller: CandidateController) -> UInt {
            UInt(candidates.count)
        }

        func candidateController(_ controller: CandidateController, candidateAtIndex index: UInt) -> String {
            candidates[Int(index)]
        }

        func candidateController(_ controller: CandidateController, didSelectCandidateAtIndex index: UInt) {
            selected = candidates[Int(index)]
        }

        func candidateController(_ controller: CandidateController, readingAtIndex index: UInt) -> String? {
            nil
        }

        func candidateController(
            _ controller: CandidateUI.CandidateController, requestExplanationFor candidate: String,
            reading: String
        ) -> String? {
            nil
        }
    }

    private func makeKeyLabels() -> [CandidateKeyLabel] {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map {
            CandidateKeyLabel(key: $0, displayedText: $0)
        }
    }

    @Test("Test if the first candidate is selected after reloading data")
    func testReloadData() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()
        #expect(controller.selectedCandidateIndex == 0)
    }

    @Test("Test 2D navigation right and left")
    func test2DNavigationRightLeft() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()
        #expect(controller.selectedCandidateIndex == 0)

        // Right moves +1 within row
        var result = controller.highlightCandidateRight()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 1)

        result = controller.highlightCandidateRight()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 2)

        // Left moves -1
        result = controller.highlightCandidateLeft()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 1)

        result = controller.highlightCandidateLeft()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 0)

        // Left at 0 stays at 0
        result = controller.highlightCandidateLeft()
        #expect(result == false)
        #expect(controller.selectedCandidateIndex == 0)
    }

    @Test("Test 2D navigation down and up")
    func test2DNavigationDownUp() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()
        #expect(controller.selectedCandidateIndex == 0)

        // Down from row 0, col 0 moves to row 1, col 0 (+5)
        var result = controller.highlightCandidateDown()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 5)

        // Up moves back to row 0, col 0 (-5)
        result = controller.highlightCandidateUp()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 0)

        // Up at row 0 stays at 0
        result = controller.highlightCandidateUp()
        #expect(result == false)
        #expect(controller.selectedCandidateIndex == 0)
    }

    @Test("Test pagination next page and previous page")
    func testPagination() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()
        #expect(controller.selectedCandidateIndex == 0)

        // Next page moves to index 10 (page 2)
        var result = controller.showNextPage()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 10)

        // Next page moves to index 20 (page 3)
        result = controller.showNextPage()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 20)

        // Next page from last page returns false
        result = controller.showNextPage()
        #expect(result == false)
        #expect(controller.selectedCandidateIndex == 20)

        // Previous page moves back to index 10
        result = controller.showPreviousPage()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 10)

        // Previous page moves back to index 0
        result = controller.showPreviousPage()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 0)

        // Previous page at first page returns false
        result = controller.showPreviousPage()
        #expect(result == false)
        #expect(controller.selectedCandidateIndex == 0)
    }

    @Test("Test keycap index translation")
    func testKeyLabelIndex() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()

        // Page 1: index 0..9
        #expect(controller.candidateIndexAtKeyLabelIndex(0) == 0)
        #expect(controller.candidateIndexAtKeyLabelIndex(4) == 4)
        #expect(controller.candidateIndexAtKeyLabelIndex(9) == 9)

        // Move to Page 2 (index 10..19)
        _ = controller.showNextPage()
        #expect(controller.candidateIndexAtKeyLabelIndex(0) == 10)
        #expect(controller.candidateIndexAtKeyLabelIndex(5) == 15)
        #expect(controller.candidateIndexAtKeyLabelIndex(9) == 19)
    }

    @Test("Test positioning within screen bounds")
    func testPositioning() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()
        controller.visible = true

        controller.set(
            windowTopLeftPoint: NSPoint(x: -100, y: 0), bottomOutOfScreenAdjustmentHeight: 10)
        Thread.sleep(forTimeInterval: 0.1)
        #expect(controller.window?.frame.minX ?? -1 >= 0)
    }
}
