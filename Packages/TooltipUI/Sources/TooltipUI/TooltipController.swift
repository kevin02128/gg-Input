// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import Cocoa

/// The window controller for showing tooltips.
public class TooltipController: NSWindowController {
    private var visualEffectView: NSVisualEffectView
    private var messageTextField: NSTextField
    private var tooltip: String = "" {
        didSet {
            messageTextField.stringValue = tooltip
            adjustSize()
        }
    }

    /// Creates a new instance.
    public init() {
        let contentRect = NSRect(x: 128.0, y: 128.0, width: 300.0, height: 26.0)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let panel = NSPanel(
            contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
        panel.level = NSWindow.Level(Int(kCGPopUpMenuWindowLevel) + 1)
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300.0, height: 26.0))
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .popover
        visualEffectView.state = .active
        visualEffectView.maskImage = .mask(withCornerRadius: 8.0)
        panel.contentView = visualEffectView

        messageTextField = NSTextField()
        messageTextField.isEditable = false
        messageTextField.isSelectable = false
        messageTextField.isBezeled = false
        messageTextField.textColor = .labelColor
        messageTextField.drawsBackground = false
        messageTextField.font = .systemFont(ofSize: 13, weight: .medium)
        visualEffectView.addSubview(messageTextField)

        super.init(window: panel)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Present the tooltip window with a given text and a location.
    ///
    /// - Parameters:
    ///   - tooltip: The text to display.
    ///   - point: The origin of the window.
    @objc(showTooltip:atPoint:)
    public func show(tooltip: String, at point: NSPoint) {
        self.tooltip = tooltip
        window?.orderFront(nil)
        set(windowLocation: point)
    }

    /// Hide the tooltip window.
    @objc
    public func hide() {
        window?.orderOut(nil)
    }

    /// Set the location of the tooltip window.
    ///
    /// - Parameter windowTopLeftPoint: The given origin.
    private func set(windowLocation windowTopLeftPoint: NSPoint) {

        var adjustedPoint = windowTopLeftPoint
        adjustedPoint.y -= 5

        var screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        for screen in NSScreen.screens {
            let frame = screen.visibleFrame
            if windowTopLeftPoint.x >= frame.minX && windowTopLeftPoint.x <= frame.maxX
                && windowTopLeftPoint.y >= frame.minY && windowTopLeftPoint.y <= frame.maxY
            {
                screenFrame = frame
                break
            }
        }

        let windowSize = window?.frame.size ?? NSSize.zero

        // bottom beneath the screen?
        if adjustedPoint.y - windowSize.height < screenFrame.minY {
            adjustedPoint.y = screenFrame.minY + windowSize.height
        }

        // top over the screen?
        if adjustedPoint.y >= screenFrame.maxY {
            adjustedPoint.y = screenFrame.maxY - 1.0
        }

        // right
        if adjustedPoint.x + windowSize.width >= screenFrame.maxX {
            adjustedPoint.x = screenFrame.maxX - windowSize.width
        }

        // left
        if adjustedPoint.x < screenFrame.minX {
            adjustedPoint.x = screenFrame.minX
        }

        window?.setFrameTopLeftPoint(adjustedPoint)

    }

    private func adjustSize() {
        let attrString = messageTextField.attributedStringValue
        let textPaddingH: CGFloat = 16.0
        let textPaddingV: CGFloat = 8.0
        var textSize = attrString.boundingRect(
            with: NSSize(width: 1600.0, height: 1600.0), options: .usesLineFragmentOrigin).size
        textSize.width = ceil(textSize.width)
        textSize.height = ceil(textSize.height)

        let totalWidth = textSize.width + textPaddingH
        let totalHeight = max(26.0, textSize.height + textPaddingV)

        let windowRect = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        visualEffectView.frame = windowRect
        visualEffectView.maskImage = .mask(withCornerRadius: min(totalHeight / 2.0, 8.0))
        messageTextField.frame = NSRect(
            x: textPaddingH / 2.0,
            y: (totalHeight - textSize.height) / 2.0,
            width: textSize.width,
            height: textSize.height
        )
        window?.setFrame(windowRect, display: true)
    }

}

private extension NSImage {
    static func mask(withCornerRadius radius: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: radius * 2, height: radius * 2), flipped: false) {
            NSColor.black.set()
            NSBezierPath(roundedRect: $0, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
