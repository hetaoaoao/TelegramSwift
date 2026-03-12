import Foundation
import Cocoa
import TGUIKit

final class MarkdownTableLayout {
    let table: MarkdownTable
    let columnWidths: [CGFloat]
    let rowHeights: [CGFloat]
    let headerHeight: CGFloat
    let size: NSSize
    let font: NSFont
    let headerFont: NSFont
    let textColor: NSColor
    let headerTextColor: NSColor
    let headerBackgroundColor: NSColor
    let borderColor: NSColor

    private static let cellPaddingH: CGFloat = 12
    private static let cellPaddingV: CGFloat = 10
    private static let minColumnWidth: CGFloat = 40

    init(table: MarkdownTable, width: CGFloat, font: NSFont, headerFont: NSFont, textColor: NSColor, headerTextColor: NSColor, headerBackgroundColor: NSColor, borderColor: NSColor) {
        self.table = table
        self.font = font
        self.headerFont = headerFont
        self.textColor = textColor
        self.headerTextColor = headerTextColor
        self.headerBackgroundColor = headerBackgroundColor
        self.borderColor = borderColor

        let paddingH = MarkdownTableLayout.cellPaddingH
        let paddingV = MarkdownTableLayout.cellPaddingV

        // Measure each column's max content width
        var colWidths = [CGFloat](repeating: 0, count: table.columnCount)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let headerAttrs: [NSAttributedString.Key: Any] = [.font: headerFont]

        for (col, header) in table.headers.enumerated() {
            let textSize = (header as NSString).size(withAttributes: headerAttrs)
            colWidths[col] = max(colWidths[col], ceil(textSize.width))
        }
        for row in table.rows {
            for (col, cell) in row.enumerated() where col < table.columnCount {
                let textSize = (cell as NSString).size(withAttributes: attrs)
                colWidths[col] = max(colWidths[col], ceil(textSize.width))
            }
        }

        // Add padding
        colWidths = colWidths.map { max($0 + paddingH * 2, MarkdownTableLayout.minColumnWidth) }

        // Scale down if total width exceeds available width
        let totalNatural = colWidths.reduce(0, +)
        if totalNatural > width && width > 0 {
            let scale = width / totalNatural
            colWidths = colWidths.map { max(floor($0 * scale), MarkdownTableLayout.minColumnWidth) }
        }

        self.columnWidths = colWidths

        // Measure row heights (support multi-line cells)
        let totalWidth = colWidths.reduce(0, +)

        func measureRowHeight(cells: [String], cellFont: NSFont) -> CGFloat {
            var maxH: CGFloat = 0
            for (col, cell) in cells.enumerated() where col < table.columnCount {
                let cellWidth = colWidths[col] - paddingH * 2
                let boundingRect = (cell as NSString).boundingRect(
                    with: NSSize(width: max(cellWidth, 1), height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: cellFont]
                )
                maxH = max(maxH, ceil(boundingRect.height))
            }
            return maxH + paddingV * 2
        }

        self.headerHeight = measureRowHeight(cells: table.headers, cellFont: headerFont)
        var rHeights: [CGFloat] = []
        for row in table.rows {
            rHeights.append(measureRowHeight(cells: row, cellFont: font))
        }
        self.rowHeights = rHeights

        let totalHeight = headerHeight + rHeights.reduce(0, +)
        self.size = NSSize(width: min(totalWidth, width > 0 ? width : totalWidth), height: totalHeight)
    }
}

final class MarkdownTableView: View {

    private var tableLayout: MarkdownTableLayout?

    func update(_ layout: MarkdownTableLayout) {
        self.tableLayout = layout
        self.setFrameSize(layout.size)
        self.layer?.setNeedsDisplay()
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        guard let layout = tableLayout else { return }

        let table = layout.table
        let paddingH = CGFloat(12)
        let borderWidth: CGFloat = 1.0
        ctx.saveGState()

        // View base class has isFlipped = true, so the context is already
        // in flipped coordinates (y=0 at top). No manual transform needed.

        let totalWidth = layout.size.width
        var y: CGFloat = 0

        // Draw header background
        let headerRect = CGRect(x: 0, y: y, width: totalWidth, height: layout.headerHeight)
        ctx.setFillColor(layout.headerBackgroundColor.cgColor)
        ctx.fill(headerRect)

        // Draw header cells
        drawRow(cells: table.headers, alignments: table.alignments, columnWidths: layout.columnWidths, y: y, rowHeight: layout.headerHeight, font: layout.headerFont, textColor: layout.headerTextColor, paddingH: paddingH, in: ctx)

        y += layout.headerHeight

        // Draw header bottom border
        ctx.setStrokeColor(layout.borderColor.cgColor)
        ctx.setLineWidth(1.0)
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: totalWidth, y: y))
        ctx.strokePath()

        // Draw data rows
        for (rowIdx, row) in table.rows.enumerated() {
            let rowHeight = layout.rowHeights[rowIdx]

            drawRow(cells: row, alignments: table.alignments, columnWidths: layout.columnWidths, y: y, rowHeight: rowHeight, font: layout.font, textColor: layout.textColor, paddingH: paddingH, in: ctx)

            y += rowHeight

            // Row separator
            ctx.setStrokeColor(layout.borderColor.cgColor)
            ctx.setLineWidth(borderWidth)
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: totalWidth, y: y))
            ctx.strokePath()
        }

        // Draw vertical column separator lines
        ctx.setStrokeColor(layout.borderColor.cgColor)
        ctx.setLineWidth(borderWidth)
        var colX: CGFloat = 0
        for col in 0 ..< layout.columnWidths.count - 1 {
            colX += layout.columnWidths[col]
            ctx.move(to: CGPoint(x: colX, y: 0))
            ctx.addLine(to: CGPoint(x: colX, y: layout.size.height))
            ctx.strokePath()
        }

        // Draw outer border
        ctx.setStrokeColor(layout.borderColor.cgColor)
        ctx.setLineWidth(borderWidth)
        ctx.stroke(CGRect(x: 0, y: 0, width: totalWidth, height: layout.size.height))

        ctx.restoreGState()
    }

    private func drawRow(cells: [String], alignments: [MarkdownTable.Alignment], columnWidths: [CGFloat], y: CGFloat, rowHeight: CGFloat, font: NSFont, textColor: NSColor, paddingH: CGFloat, in ctx: CGContext) {
        let paddingV: CGFloat = 10
        var x: CGFloat = 0
        for (col, cell) in cells.enumerated() where col < columnWidths.count {
            let colWidth = columnWidths[col]
            let cellContentWidth = colWidth - paddingH * 2

            let attrString = NSAttributedString(string: cell, attributes: [
                .font: font,
                .foregroundColor: textColor
            ])

            let boundingRect = attrString.boundingRect(
                with: NSSize(width: max(cellContentWidth, 1), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )

            let alignment = col < alignments.count ? alignments[col] : .left
            let textX: CGFloat
            switch alignment {
            case .left:
                textX = x + paddingH
            case .center:
                textX = x + paddingH + (cellContentWidth - boundingRect.width) / 2
            case .right:
                textX = x + paddingH + (cellContentWidth - boundingRect.width)
            }
            let textY = y + paddingV

            let textRect = CGRect(x: textX, y: textY, width: cellContentWidth, height: rowHeight - paddingV * 2)

            // Use NSGraphicsContext for correct text rendering in flipped context
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            attrString.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            NSGraphicsContext.restoreGraphicsState()

            x += colWidth
        }
    }

}
