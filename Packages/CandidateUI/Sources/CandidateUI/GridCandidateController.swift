// Copyright (c) 2026 wtf. All rights reserved.
// GridCandidateController.swift - Apple-style 2D Matrix (Grid) Candidate Window

import Cocoa

private protocol GridCandidateViewDelegate: AnyObject {
    func view(
        _ view: GridCandidateView, didRequestExplanationFor candidate: String, reading: String
    ) -> String?
}

private class GridCandidateView: NSView {
    fileprivate weak var delegate: GridCandidateViewDelegate?

    var highlightedIndex: UInt = 0 {
        didSet {
            setNeedsDisplay(bounds)
        }
    }

    var action: Selector?
    weak var target: AnyObject?

    var columns: Int = 6
    var maxRows: Int = 5
    var isExpanded: Bool = false
    var keyLabels: [String] = []
    var displayedCandidates: [(candidate: String, reading: String?)] = []

    private var keyLabelFont: NSFont = .systemFont(ofSize: 11, weight: .regular)
    private var candidateFont: NSFont = .systemFont(ofSize: 17, weight: .regular)
    private var cellPaddingH: CGFloat = 8.0
    private var cellPaddingV: CGFloat = 6.0
    private var cellWidth: CGFloat = 58.0
    private var cellHeight: CGFloat = 34.0
    private let gridMargin: CGFloat = 8.0

    private var keyLabelAttrNormal: [NSAttributedString.Key: AnyObject] = [:]
    private var keyLabelAttrHighlighted: [NSAttributedString.Key: AnyObject] = [:]
    private var candidateAttrNormal: [NSAttributedString.Key: AnyObject] = [:]
    private var candidateAttrHighlighted: [NSAttributedString.Key: AnyObject] = [:]

    private var tooltipSize: NSSize = .zero

    override var toolTip: String? {
        didSet {
            if let toolTip = toolTip, !toolTip.isEmpty {
                let baseSize = NSSize(width: 10240.0, height: 10240.0)
                var rect = (toolTip as NSString).boundingRect(
                    with: baseSize, options: .usesLineFragmentOrigin, attributes: keyLabelAttrNormal
                )
                rect.size.height += 6.0
                rect.size.width += 12.0
                tooltipSize = rect.size
            } else {
                tooltipSize = .zero
            }
        }
    }

    override var isFlipped: Bool {
        true
    }

    var activeRows: Int {
        if !isExpanded {
            return 1
        }
        let count = displayedCandidates.count
        return max(1, min(maxRows, (count + columns - 1) / columns))
    }

    var sizeForGrid: NSSize {
        let count = displayedCandidates.count
        if count == 0 {
            return .zero
        }
        let activeCols = min(count, columns)
        let rowsCount = activeRows

        let totalWidth = gridMargin * 2 + CGFloat(activeCols) * cellWidth
        let totalHeight = gridMargin * 2 + CGFloat(rowsCount) * cellHeight + tooltipSize.height
        return NSSize(width: max(totalWidth, tooltipSize.width + gridMargin * 2), height: totalHeight)
    }

    func set(keyLabelFont: NSFont, candidateFont: NSFont) {
        self.keyLabelFont = keyLabelFont
        self.candidateFont = candidateFont

        let para = NSMutableParagraphStyle()
        para.alignment = .center

        keyLabelAttrNormal = [
            .font: keyLabelFont,
            .paragraphStyle: para,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        keyLabelAttrHighlighted = [
            .font: keyLabelFont,
            .paragraphStyle: para,
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        candidateAttrNormal = [
            .font: candidateFont,
            .paragraphStyle: para,
            .foregroundColor: NSColor.labelColor,
        ]
        candidateAttrHighlighted = [
            .font: candidateFont,
            .paragraphStyle: para,
            .foregroundColor: NSColor.white,
        ]
    }

    func set(
        keyLabels labels: [String],
        displayedCandidates candidates: [(candidate: String, reading: String?)]
    ) {
        let maxItems = isExpanded ? (columns * maxRows) : columns
        let count = min(candidates.count, maxItems)
        self.keyLabels = labels
        self.displayedCandidates = Array(candidates.prefix(count))

        // Measure maximum text widths across candidates to size cells harmoniously
        let baseSize = NSSize(width: 10240.0, height: 10240.0)
        var maxCandWidth: CGFloat = 30.0
        var maxCandHeight: CGFloat = candidateFont.pointSize * 1.3
        for item in self.displayedCandidates {
            let rect = (item.candidate as NSString).boundingRect(
                with: baseSize, options: .usesLineFragmentOrigin, attributes: candidateAttrNormal
            )
            maxCandWidth = max(maxCandWidth, rect.width)
            maxCandHeight = max(maxCandHeight, rect.height)
        }

        cellWidth = max(54.0, ceil(maxCandWidth + keyLabelFont.pointSize + cellPaddingH * 2))
        cellHeight = max(34.0, ceil(maxCandHeight + cellPaddingV))
    }

    override func draw(_ dirtyRect: NSRect) {
        if let toolTip = toolTip, !toolTip.isEmpty {
            let tooltipFrame = NSRect(
                x: gridMargin, y: gridMargin, width: bounds.width - gridMargin * 2, height: tooltipSize.height
            )
            (toolTip as NSString).draw(in: tooltipFrame, withAttributes: keyLabelAttrNormal)
        }

        let offsetY = gridMargin + tooltipSize.height
        let count = displayedCandidates.count
        let highlightedRow = Int(highlightedIndex) / columns

        for i in 0..<count {
            let col = i % columns
            let row = i / columns

            let cellRect = NSRect(
                x: gridMargin + CGFloat(col) * cellWidth,
                y: offsetY + CGFloat(row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            )

            let isHighlighted = (UInt(i) == highlightedIndex)
            if isHighlighted {
                let capsule = cellRect.insetBy(dx: 2.0, dy: 2.0)
                let path = NSBezierPath(roundedRect: capsule, xRadius: 6.0, yRadius: 6.0)
                NSColor.controlAccentColor.setFill()
                path.fill()
            }

            // Keycap badge corresponds to column (1 to 6)
            let label = col < keyLabels.count ? keyLabels[col] : ""
            let keycapWidth: CGFloat = 16.0
            let keycapHeight: CGFloat = 16.0
            let keycapRect = NSRect(
                x: cellRect.minX + 4.0,
                y: cellRect.midY - keycapHeight / 2.0,
                width: keycapWidth,
                height: keycapHeight
            )

            // Show badge background if highlighted or on current highlighted row
            if !isHighlighted && !label.isEmpty {
                if !isExpanded || row == highlightedRow {
                    let badgePath = NSBezierPath(roundedRect: keycapRect, xRadius: 3.5, yRadius: 3.5)
                    NSColor.quaternaryLabelColor.setFill()
                    badgePath.fill()
                }
            }

            let keyAttr = isHighlighted ? keyLabelAttrHighlighted : keyLabelAttrNormal
            let labelTextRect = NSRect(
                x: keycapRect.minX,
                y: keycapRect.midY - (keyLabelFont.pointSize * 1.2) / 2.0 - 0.5,
                width: keycapWidth,
                height: keyLabelFont.pointSize * 1.2
            )
            (label as NSString).draw(in: labelTextRect, withAttributes: keyAttr)

            // Draw Candidate text in the remaining space of the cell
            let candidate = displayedCandidates[i].candidate
            let candAttr = isHighlighted ? candidateAttrHighlighted : candidateAttrNormal
            let candTextX = cellRect.minX + keycapWidth + 5.0
            let candTextW = max(10.0, cellRect.maxX - candTextX - 4.0)
            let candTextRect = NSRect(
                x: candTextX,
                y: cellRect.midY - (candidateFont.pointSize * 1.3) / 2.0,
                width: candTextW,
                height: candidateFont.pointSize * 1.3
            )
            (candidate as NSString).draw(in: candTextRect, withAttributes: candAttr)
        }
    }

    fileprivate func findHitIndex(event: NSEvent) -> UInt? {
        let location = convert(event.locationInWindow, to: nil)
        let offsetY = gridMargin + tooltipSize.height
        let count = displayedCandidates.count

        for i in 0..<count {
            let col = i % columns
            let row = i / columns
            let cellRect = NSRect(
                x: gridMargin + CGFloat(col) * cellWidth,
                y: offsetY + CGFloat(row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            )
            if cellRect.contains(location) {
                return UInt(i)
            }
        }
        return nil
    }

    override func mouseUp(with event: NSEvent) {
        guard let index = findHitIndex(event: event) else {
            return
        }
        highlightedIndex = index
        if let target = target, let action = action {
            _ = target.perform(action, with: self)
        }
    }
}

/// Apple-style 2D Matrix Grid Candidate Window Controller
/// Supports 1-row initial state and dynamic expansion to 6 columns x 5 rows (30 items).
@objc(VTGridCandidateController)
public class GridCandidateController: CandidateController {
    private var gridView: GridCandidateView
    private var prevPageButton: NSButton
    private var nextPageButton: NSButton
    private var pageLabel: NSTextField
    private var expandButton: NSButton
    private var currentPage: UInt = 0

    private var lastTopLeftPoint: NSPoint?
    private var lastAdjustmentHeight: CGFloat = 0.0

    public let columns: Int = 6
    public let rows: Int = 5

    @objc public var isExpanded: Bool = false {
        didSet {
            gridView.isExpanded = isExpanded
            updateExpandButton()
        }
    }

    public var itemsPerPage: Int {
        isExpanded ? (columns * rows) : columns
    }

    public init() {
        var contentRect = NSRect(x: 128.0, y: 128.0, width: 380.0, height: 60.0)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let panel = NSPanel(
            contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false
        )
        panel.level = NSWindow.Level(Int(kCGPopUpMenuWindowLevel) + 1)
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380.0, height: 60.0))
        effect.blendingMode = .behindWindow
        effect.material = .popover
        effect.state = .active
        effect.maskImage = .mask(withCornerRadius: 10.0)
        panel.contentView = effect

        contentRect.origin = .zero
        gridView = GridCandidateView(frame: contentRect)
        gridView.columns = columns
        gridView.maxRows = rows
        gridView.isExpanded = false
        panel.contentView?.addSubview(gridView)

        expandButton = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        expandButton.setButtonType(.momentaryLight)
        expandButton.bezelStyle = .inline
        expandButton.isBordered = false
        expandButton.imagePosition = .imageOnly
        expandButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Expand")
        panel.contentView?.addSubview(expandButton)

        nextPageButton = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 20))
        nextPageButton.setButtonType(.momentaryLight)
        nextPageButton.bezelStyle = .smallSquare
        nextPageButton.isBordered = false
        nextPageButton.title = "»"

        prevPageButton = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 20))
        prevPageButton.setButtonType(.momentaryLight)
        prevPageButton.bezelStyle = .smallSquare
        prevPageButton.isBordered = false
        prevPageButton.title = "«"

        pageLabel = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 16))
        pageLabel.isEditable = false
        pageLabel.isSelectable = false
        pageLabel.isBezeled = false
        pageLabel.drawsBackground = false
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.alignment = .center
        pageLabel.font = .systemFont(ofSize: 11, weight: .regular)

        panel.contentView?.addSubview(prevPageButton)
        panel.contentView?.addSubview(pageLabel)
        panel.contentView?.addSubview(nextPageButton)

        super.init(window: panel)

        // Default 6 candidate keys for matrix columns: 1 to 6
        keyLabels = ["1", "2", "3", "4", "5", "6"].map {
            CandidateKeyLabel(key: $0, displayedText: $0)
        }

        gridView.target = self
        gridView.action = #selector(candidateViewMouseDidClick(_:))
        expandButton.target = self
        expandButton.action = #selector(toggleExpandAction(_:))
        nextPageButton.target = self
        nextPageButton.action = #selector(pageButtonAction(_:))
        prevPageButton.target = self
        prevPageButton.action = #selector(pageButtonAction(_:))
        gridView.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateExpandButton() {
        let symbolName = isExpanded ? "chevron.up" : "chevron.down"
        let desc = isExpanded ? "Collapse" : "Expand"
        expandButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: desc)
    }

    override public func reloadData() {
        // Reset to Apple-style 1-row default collapsed state
        isExpanded = false
        currentPage = 0
        gridView.highlightedIndex = 0
        layoutGridView()
    }

    override func doSet(windowTopLeftPoint: NSPoint, bottomOutOfScreenAdjustmentHeight height: CGFloat) {
        lastTopLeftPoint = windowTopLeftPoint
        lastAdjustmentHeight = height
        super.doSet(windowTopLeftPoint: windowTopLeftPoint, bottomOutOfScreenAdjustmentHeight: height)
    }

    @objc override public func toggleExpand() {
        guard let delegate = delegate else { return }
        let total = delegate.candidateCountForController(self)
        if total <= UInt(columns) && !isExpanded {
            return
        }
        let currentIndex = selectedCandidateIndex
        isExpanded.toggle()
        selectedCandidateIndex = currentIndex
    }

    override public func showNextPage() -> Bool {
        guard delegate != nil, currentPage + 1 < pageCount else {
            return false
        }
        currentPage += 1
        gridView.highlightedIndex = 0
        layoutGridView()
        return true
    }

    override public func showPreviousPage() -> Bool {
        guard delegate != nil, currentPage > 0 else {
            return false
        }
        currentPage -= 1
        gridView.highlightedIndex = 0
        layoutGridView()
        return true
    }

    override public func highlightNextCandidate() -> Bool {
        guard let delegate = delegate else { return false }
        let current = selectedCandidateIndex
        let total = delegate.candidateCountForController(self)
        if current + 1 >= total {
            return false
        }
        selectedCandidateIndex = current + 1
        return true
    }

    override public func highlightPreviousCandidate() -> Bool {
        let current = selectedCandidateIndex
        if current == 0 {
            return false
        }
        selectedCandidateIndex = current - 1
        return true
    }

    override public func highlightCandidateRight() -> Bool {
        highlightNextCandidate()
    }

    override public func highlightCandidateLeft() -> Bool {
        highlightPreviousCandidate()
    }

    override public func highlightCandidateDown() -> Bool {
        guard let delegate = delegate else { return false }
        let total = delegate.candidateCountForController(self)
        guard total > 0 else { return false }

        if !isExpanded {
            // First time pressing down in candidate mode: expand 6x5 matrix
            guard total > UInt(columns) else {
                return false
            }
            let current = selectedCandidateIndex
            isExpanded = true
            let targetIndex = current + UInt(columns)
            if targetIndex < total {
                selectedCandidateIndex = targetIndex
            } else {
                layoutGridView()
            }
            return true
        }

        // Already expanded: move down one row (+6)
        let current = selectedCandidateIndex
        let targetIndex = current + UInt(columns)
        if targetIndex < total {
            selectedCandidateIndex = targetIndex
            return true
        } else if currentPage + 1 < pageCount {
            return showNextPage()
        }
        return false
    }

    override public func highlightCandidateUp() -> Bool {
        guard let delegate = delegate else { return false }
        guard isExpanded else {
            // In 1-row mode, cannot move up
            return false
        }

        let current = selectedCandidateIndex
        let rowOnPage = (current % UInt(itemsPerPage)) / UInt(columns)

        if rowOnPage > 0 && current >= UInt(columns) {
            selectedCandidateIndex = current - UInt(columns)
            return true
        }

        // On row 0:
        if currentPage > 0 {
            // Move to previous page
            _ = showPreviousPage()
            let total = delegate.candidateCountForController(self)
            let pageStart = currentPage * UInt(itemsPerPage)
            let remaining = total - pageStart
            let pageRows = (remaining + UInt(columns) - 1) / UInt(columns)
            let lastRow = min(UInt(rows - 1), pageRows - 1)
            let col = current % UInt(columns)
            let target = pageStart + lastRow * UInt(columns) + col
            selectedCandidateIndex = min(target, total - 1)
            return true
        } else {
            // On row 0 of page 0: COLLAPSE BACK TO 1 ROW!
            let col = current % UInt(columns)
            isExpanded = false
            selectedCandidateIndex = col
            return true
        }
    }

    override public func candidateIndexAtKeyLabelIndex(_ index: UInt) -> UInt {
        guard let delegate = delegate, index < UInt(columns) else { return UInt.max }
        let total = delegate.candidateCountForController(self)

        if !isExpanded {
            let result = currentPage * UInt(itemsPerPage) + index
            return result < total ? result : UInt.max
        } else {
            let currentRow = (gridView.highlightedIndex) / UInt(columns)
            let result = currentPage * UInt(itemsPerPage) + currentRow * UInt(columns) + index
            return result < total ? result : UInt.max
        }
    }

    override public var selectedCandidateIndex: UInt {
        get {
            currentPage * UInt(itemsPerPage) + gridView.highlightedIndex
        }
        set {
            guard let delegate = delegate else { return }
            let total = delegate.candidateCountForController(self)
            if newValue < total {
                let perPage = UInt(itemsPerPage)
                currentPage = newValue / perPage
                gridView.highlightedIndex = newValue % perPage
                layoutGridView()
            }
        }
    }

    private var pageCount: UInt {
        guard let delegate = delegate else { return 0 }
        let total = delegate.candidateCountForController(self)
        let perPage = UInt(itemsPerPage)
        guard perPage > 0 else { return 0 }
        return total / perPage + ((total % perPage) != 0 ? 1 : 0)
    }

    private func layoutGridView() {
        guard let delegate = delegate else { return }
        gridView.set(keyLabelFont: keyLabelFont, candidateFont: candidateFont)

        var candidates = [(candidate: String, reading: String?)]()
        let totalCount = delegate.candidateCountForController(self)
        let perPage = UInt(itemsPerPage)

        let start = currentPage * perPage
        for i in start..<min(start + perPage, totalCount) {
            let text = delegate.candidateController(self, candidateAtIndex: i)
            let reading = delegate.candidateController(self, readingAtIndex: i)
            candidates.append((text, reading))
        }

        // Use the first `columns` keys for matrix labels
        let colLabels = Array(keyLabels.prefix(columns)).map { $0.displayedText }
        gridView.set(
            keyLabels: colLabels,
            displayedCandidates: candidates
        )
        gridView.toolTip = tooltip

        let gridNaturalSize = gridView.sizeForGrid
        let hasMoreCandidates = (totalCount > UInt(columns))
        let showPagination = (pageCount > 1)
        let bottomBarHeight: CGFloat = showPagination ? 24.0 : 0.0

        let expandBtnWidth: CGFloat = hasMoreCandidates ? 26.0 : 0.0
        let windowWidth = max(gridNaturalSize.width + expandBtnWidth, showPagination ? 160.0 : 80.0)
        let windowHeight = gridNaturalSize.height + bottomBarHeight

        gridView.frame = NSRect(x: 0, y: bottomBarHeight, width: gridNaturalSize.width, height: gridNaturalSize.height)

        expandButton.isHidden = !hasMoreCandidates
        if hasMoreCandidates {
            expandButton.frame = NSRect(
                x: windowWidth - 25.0,
                y: windowHeight - 28.0,
                width: 22.0,
                height: 22.0
            )
        }

        prevPageButton.isHidden = !showPagination
        nextPageButton.isHidden = !showPagination
        pageLabel.isHidden = !showPagination

        if showPagination {
            prevPageButton.isEnabled = (currentPage > 0)
            nextPageButton.isEnabled = (currentPage + 1 < pageCount)
            pageLabel.stringValue = "\(currentPage + 1) / \(pageCount)"

            let midX = windowWidth / 2.0
            pageLabel.frame = NSRect(x: midX - 30.0, y: 3.0, width: 60.0, height: 18.0)
            prevPageButton.frame = NSRect(x: midX - 60.0, y: 3.0, width: 26.0, height: 18.0)
            nextPageButton.frame = NSRect(x: midX + 34.0, y: 3.0, width: 26.0, height: 18.0)
        }

        window?.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        window?.contentView?.setFrameSize(NSSize(width: windowWidth, height: windowHeight))

        // Keep anchored to the last input origin
        if let pt = lastTopLeftPoint {
            super.doSet(windowTopLeftPoint: pt, bottomOutOfScreenAdjustmentHeight: lastAdjustmentHeight)
        }
    }

    @objc private func candidateViewMouseDidClick(_ sender: Any) {
        delegate?.candidateController(self, didSelectCandidateAtIndex: selectedCandidateIndex)
    }

    @objc private func toggleExpandAction(_ sender: Any) {
        toggleExpand()
    }

    @objc private func pageButtonAction(_ sender: NSButton) {
        if sender == nextPageButton {
            _ = showNextPage()
        } else if sender == prevPageButton {
            _ = showPreviousPage()
        }
    }
}

extension GridCandidateController: GridCandidateViewDelegate {
    fileprivate func view(
        _ view: GridCandidateView, didRequestExplanationFor candidate: String, reading: String
    ) -> String? {
        delegate?.candidateController(self, requestExplanationFor: candidate, reading: reading)
    }
}
