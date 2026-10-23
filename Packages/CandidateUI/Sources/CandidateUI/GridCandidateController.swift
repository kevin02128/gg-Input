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

    var columns: Int = 5
    var rows: Int = 2
    var keyLabels: [String] = []
    var displayedCandidates: [(candidate: String, reading: String?)] = []

    private var keyLabelFont: NSFont = .systemFont(ofSize: 12, weight: .regular)
    private var candidateFont: NSFont = .systemFont(ofSize: 17, weight: .regular)
    private var cellPaddingH: CGFloat = 12.0
    private var cellPaddingV: CGFloat = 8.0
    private var cellWidth: CGFloat = 64.0
    private var cellHeight: CGFloat = 36.0
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

    var sizeForGrid: NSSize {
        let count = min(displayedCandidates.count, columns * rows)
        if count == 0 {
            return .zero
        }
        let activeCols = min(count, columns)
        let activeRows = max(1, (count + columns - 1) / columns)

        let totalWidth = gridMargin * 2 + CGFloat(activeCols) * cellWidth
        let totalHeight = gridMargin * 2 + CGFloat(activeRows) * cellHeight + tooltipSize.height
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
        let maxItems = columns * rows
        let count = min(labels.count, min(candidates.count, maxItems))
        self.keyLabels = Array(labels.prefix(count))
        self.displayedCandidates = Array(candidates.prefix(count))

        // Measure maximum text widths across candidates to size cells harmoniously
        let baseSize = NSSize(width: 10240.0, height: 10240.0)
        var maxCandWidth: CGFloat = 36.0
        var maxCandHeight: CGFloat = candidateFont.pointSize * 1.3
        for item in self.displayedCandidates {
            let rect = (item.candidate as NSString).boundingRect(
                with: baseSize, options: .usesLineFragmentOrigin, attributes: candidateAttrNormal
            )
            maxCandWidth = max(maxCandWidth, rect.width)
            maxCandHeight = max(maxCandHeight, rect.height)
        }

        cellWidth = max(58.0, ceil(maxCandWidth + keyLabelFont.pointSize + cellPaddingH * 2))
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

            // Draw Keycap badge on the left side of the cell
            let label = i < keyLabels.count ? keyLabels[i] : ""
            let keycapWidth: CGFloat = 16.0
            let keycapHeight: CGFloat = 16.0
            let keycapRect = NSRect(
                x: cellRect.minX + 4.0,
                y: cellRect.midY - keycapHeight / 2.0,
                width: keycapWidth,
                height: keycapHeight
            )

            if !isHighlighted && !label.isEmpty {
                let badgePath = NSBezierPath(roundedRect: keycapRect, xRadius: 3.5, yRadius: 3.5)
                NSColor.quaternaryLabelColor.setFill()
                badgePath.fill()
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
            let candTextX = cellRect.minX + keycapWidth + 6.0
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

    private func findHitIndex(event: NSEvent) -> UInt? {
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

/// New Apple-style 2D Matrix Grid Candidate Window Controller
@objc(VTGridCandidateController)
public class GridCandidateController: CandidateController {
    private var gridView: GridCandidateView
    private var prevPageButton: NSButton
    private var nextPageButton: NSButton
    private var pageLabel: NSTextField
    private var currentPage: UInt = 0

    public let columns: Int = 5
    public let rows: Int = 2
    public var itemsPerPage: Int { columns * rows }

    public init() {
        var contentRect = NSRect(x: 128.0, y: 128.0, width: 340.0, height: 100.0)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let panel = NSPanel(
            contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false
        )
        panel.level = NSWindow.Level(Int(kCGPopUpMenuWindowLevel) + 1)
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340.0, height: 100.0))
        effect.blendingMode = .behindWindow
        effect.material = .popover
        effect.state = .active
        effect.maskImage = .mask(withCornerRadius: 12.0)
        panel.contentView = effect

        contentRect.origin = .zero
        gridView = GridCandidateView(frame: contentRect)
        gridView.columns = columns
        gridView.rows = rows
        panel.contentView?.addSubview(gridView)

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

        pageLabel = NSTextField(frame: NSRect(x: 0, y: 0, width: 44, height: 16))
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

        // Default 10 candidate keys for matrix grid: 1 to 0
        keyLabels = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map {
            CandidateKeyLabel(key: $0, displayedText: $0)
        }

        gridView.target = self
        gridView.action = #selector(candidateViewMouseDidClick(_:))
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

    override public func reloadData() {
        gridView.highlightedIndex = 0
        currentPage = 0
        layoutGridView()
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
        if current + 1 >= delegate.candidateCountForController(self) {
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
        let newIndex = selectedCandidateIndex + UInt(columns)
        if newIndex < total {
            selectedCandidateIndex = newIndex
            return true
        } else if currentPage + 1 < pageCount {
            return showNextPage()
        }
        return false
    }

    override public func highlightCandidateUp() -> Bool {
        let current = selectedCandidateIndex
        if current >= UInt(columns) {
            selectedCandidateIndex = current - UInt(columns)
            return true
        } else if currentPage > 0 {
            _ = showPreviousPage()
            return true
        }
        return false
    }

    override public func candidateIndexAtKeyLabelIndex(_ index: UInt) -> UInt {
        guard let delegate = delegate else { return UInt.max }
        let result = currentPage * UInt(itemsPerPage) + index
        return result < delegate.candidateCountForController(self) ? result : UInt.max
    }

    override public var selectedCandidateIndex: UInt {
        get {
            currentPage * UInt(itemsPerPage) + gridView.highlightedIndex
        }
        set {
            guard let delegate = delegate else { return }
            if newValue < delegate.candidateCountForController(self) {
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

        gridView.set(
            keyLabels: keyLabels.map { $0.displayedText },
            displayedCandidates: candidates
        )
        gridView.toolTip = tooltip

        let gridNaturalSize = gridView.sizeForGrid
        let showPagination = (pageCount > 1)
        let bottomBarHeight: CGFloat = showPagination ? 24.0 : 0.0

        let windowWidth = max(gridNaturalSize.width, showPagination ? 140.0 : 60.0)
        let windowHeight = gridNaturalSize.height + bottomBarHeight

        gridView.frame = NSRect(x: 0, y: bottomBarHeight, width: windowWidth, height: gridNaturalSize.height)

        prevPageButton.isHidden = !showPagination
        nextPageButton.isHidden = !showPagination
        pageLabel.isHidden = !showPagination

        if showPagination {
            prevPageButton.isEnabled = (currentPage > 0)
            nextPageButton.isEnabled = (currentPage + 1 < pageCount)
            pageLabel.stringValue = "\(currentPage + 1) / \(pageCount)"

            let midX = windowWidth / 2.0
            pageLabel.frame = NSRect(x: midX - 25.0, y: 3.0, width: 50.0, height: 18.0)
            prevPageButton.frame = NSRect(x: midX - 55.0, y: 3.0, width: 26.0, height: 18.0)
            nextPageButton.frame = NSRect(x: midX + 29.0, y: 3.0, width: 26.0, height: 18.0)
        }

        window?.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        window?.contentView?.setFrameSize(NSSize(width: windowWidth, height: windowHeight))
    }

    @objc private func candidateViewMouseDidClick(_ sender: Any) {
        delegate?.candidateController(self, didSelectCandidateAtIndex: selectedCandidateIndex)
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
