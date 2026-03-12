import Foundation
import TGUIKit

struct MarkdownTableRegion {
    let range: NSRange
    let table: MarkdownTable
}

final class MarkdownTableParser {

    static func parse(_ text: String) -> [MarkdownTableRegion] {
        let lines = splitLines(text)
        var regions: [MarkdownTableRegion] = []
        var i = 0

        while i < lines.count {
            // Need at least header + separator
            guard i + 1 < lines.count else { break }

            let headerLine = lines[i]
            let separatorLine = lines[i + 1]

            let headerCells = parsePipeRow(headerLine.text)
            let separatorCells = parsePipeRow(separatorLine.text)

            guard !headerCells.isEmpty,
                  headerCells.count == separatorCells.count,
                  isSeparatorRow(separatorCells) else {
                i += 1
                continue
            }

            let alignments = separatorCells.map { parseAlignment($0) }

            // Collect data rows
            var dataRows: [[String]] = []
            var endOffset = separatorLine.range.location + separatorLine.range.length
            var j = i + 2
            while j < lines.count {
                let rowLine = lines[j]
                let rowCells = parsePipeRow(rowLine.text)
                guard !rowCells.isEmpty else { break }
                dataRows.append(rowCells)
                endOffset = rowLine.range.location + rowLine.range.length
                j += 1
            }

            let startOffset = headerLine.range.location
            let tableRange = NSRange(location: startOffset, length: endOffset - startOffset)

            let table = MarkdownTable(headers: headerCells, alignments: alignments, rows: dataRows)
            regions.append(MarkdownTableRegion(range: tableRange, table: table))

            i = j
        }

        return regions
    }

    // MARK: - Private

    private struct Line {
        let text: String
        let range: NSRange // range in original string (excluding newline)
    }

    private static func splitLines(_ text: String) -> [Line] {
        var lines: [Line] = []
        let nsString = text as NSString
        var start = 0
        let length = nsString.length

        while start < length {
            let lineRange = nsString.lineRange(for: NSRange(location: start, length: 0))
            let end = lineRange.location + lineRange.length
            var contentEnd = end
            // Strip trailing newline from content
            if contentEnd > lineRange.location && nsString.character(at: contentEnd - 1) == 0x0A {
                contentEnd -= 1
            }
            if contentEnd > lineRange.location && nsString.character(at: contentEnd - 1) == 0x0D {
                contentEnd -= 1
            }
            let contentRange = NSRange(location: lineRange.location, length: contentEnd - lineRange.location)
            let lineText = nsString.substring(with: contentRange)
            lines.append(Line(text: lineText, range: contentRange))
            start = end
        }
        return lines
    }

    private static func parsePipeRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else {
            return []
        }
        // Remove leading and trailing pipe
        let inner = String(trimmed.dropFirst().dropLast())
        let cells = inner.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        // Must have at least 2 columns to be a meaningful table
        guard cells.count >= 2 else { return [] }
        return cells
    }

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            // Match patterns like ---, :---, :---:, ---:
            var chars = trimmed
            if chars.hasPrefix(":") { chars = String(chars.dropFirst()) }
            if chars.hasSuffix(":") { chars = String(chars.dropLast()) }
            return !chars.isEmpty && chars.allSatisfy({ $0 == "-" })
        }
    }

    private static func parseAlignment(_ cell: String) -> MarkdownTable.Alignment {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        let left = trimmed.hasPrefix(":")
        let right = trimmed.hasSuffix(":")
        if left && right { return .center }
        if right { return .right }
        return .left
    }
}
