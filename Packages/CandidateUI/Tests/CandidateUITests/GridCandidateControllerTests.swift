import Cocoa
import Testing

@testable import CandidateUI

@MainActor
@Suite("Test the Grid Candidate Controller")
final class GridCandidateControllerTests {

    class Mock: CandidateControllerDelegate {
        // 36 candidates (more than 30 to test 6x5 matrix and pagination)
        let candidates = (1...36).map { "C\($0)" }
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
        ["1", "2", "3", "4", "5", "6"].map {
            CandidateKeyLabel(key: $0, displayedText: $0)
        }
    }

    @Test("Test initial state is 1-row collapsed")
    func testInitialStateCollapsed() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()

        #expect(controller.isExpanded == false)
        #expect(controller.selectedCandidateIndex == 0)
        #expect(controller.itemsPerPage == 6)
    }

    @Test("Test pressing down expands to 6x5 matrix")
    func testDownExpandsMatrix() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()

        #expect(controller.isExpanded == false)
        #expect(controller.selectedCandidateIndex == 0)

        // First down arrow: expands to 6x5 matrix and steps to row 1 (index 6)
        let result = controller.highlightCandidateDown()
        #expect(result == true)
        #expect(controller.isExpanded == true)
        #expect(controller.selectedCandidateIndex == 6)
        #expect(controller.itemsPerPage == 30)

        // Second down arrow: steps to row 2 (index 12)
        let result2 = controller.highlightCandidateDown()
        #expect(result2 == true)
        #expect(controller.selectedCandidateIndex == 12)
    }

    @Test("Test pressing up from row 0 collapses back to 1 row")
    func testUpCollapsesMatrix() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()

        // Expand
        _ = controller.highlightCandidateDown()
        #expect(controller.isExpanded == true)
        #expect(controller.selectedCandidateIndex == 6)

        // Up steps back to row 0 (index 0)
        var result = controller.highlightCandidateUp()
        #expect(result == true)
        #expect(controller.selectedCandidateIndex == 0)
        #expect(controller.isExpanded == true)

        // Up on row 0 collapses back to 1-row mode
        result = controller.highlightCandidateUp()
        #expect(result == true)
        #expect(controller.isExpanded == false)
        #expect(controller.selectedCandidateIndex == 0)

        // Up when already collapsed returns false
        result = controller.highlightCandidateUp()
        #expect(result == false)
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

        // Left at 0 returns false
        result = controller.highlightCandidateLeft()
        #expect(result == false)
        #expect(controller.selectedCandidateIndex == 0)
    }

    @Test("Test keycap index translation in 1-row and expanded modes")
    func testKeyLabelIndex() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()

        // 1-row mode: key indices 0..5 map to candidate indices 0..5
        #expect(controller.candidateIndexAtKeyLabelIndex(0) == 0)
        #expect(controller.candidateIndexAtKeyLabelIndex(3) == 3)
        #expect(controller.candidateIndexAtKeyLabelIndex(5) == 5)

        // Expand to 6x5 matrix (selection moves to row 1, col 0 = index 6)
        _ = controller.highlightCandidateDown()
        #expect(controller.isExpanded == true)
        #expect(controller.selectedCandidateIndex == 6)

        // On row 1, key indices 0..5 map to candidate indices 6..11
        #expect(controller.candidateIndexAtKeyLabelIndex(0) == 6)
        #expect(controller.candidateIndexAtKeyLabelIndex(2) == 8)
        #expect(controller.candidateIndexAtKeyLabelIndex(5) == 11)
    }

    @Test("Test toggle expand method")
    func testToggleExpand() {
        let controller = GridCandidateController()
        let mock = Mock()
        controller.delegate = mock
        controller.keyLabels = makeKeyLabels()
        controller.reloadData()

        #expect(controller.isExpanded == false)
        controller.toggleExpand()
        #expect(controller.isExpanded == true)
        controller.toggleExpand()
        #expect(controller.isExpanded == false)
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
