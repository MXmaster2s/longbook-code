// The lines inside a picked statement: a PDF's rows rebuilt from where its text sits on
// the page, a CSV or text file as it is, an .xlsx sheet cell by cell. A locked PDF asks
// for its password; a scan is refused with the reason llms.txt already gives.
import CoreXLSX
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

public enum StatementText {
    public enum Kind: Equatable { case pdf, csv, text, xlsx, xls }

    public enum ReadError: LocalizedError, Equatable {
        case locked
        case wrongPassword
        case scanned
        case unreadable
        case unsupported(String)
        case noLines(String)

        public var errorDescription: String? {
            switch self {
            case .locked: return "This statement is locked. Enter the password the bank set for it."
            case .wrongPassword: return "That password did not open it. Banks usually say what it is in the email that carried the statement."
            case .scanned: return "This PDF is a scan with no text in it. A statement downloaded from the bank has text; a photographed one does not."
            case .unreadable: return "That file could not be read."
            case .unsupported(let ext):
                return "longbook reads PDF, CSV and Excel (.xls, .xlsx) statements; .\(ext) is not one yet."
            case .noLines(let found): return "No dated lines with amounts were found. \(found)"
            }
        }
    }

    /// What the file's extension says it is.
    public static func kind(of url: URL) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "csv": return .csv
        case "txt": return .text
        case "xlsx", "xlsm": return .xlsx
        case "xls": return .xls
        default: return nil
        }
    }

    /// The lines the file proves. Security scope is taken for the read, as a picked file
    /// outside the sandbox needs. A locked PDF throws `.locked` until a password comes.
    public static func lines(from url: URL, password: String? = nil) throws -> [StatementLine] {
        guard let kind = kind(of: url) else { throw ReadError.unsupported(url.pathExtension.lowercased()) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let lines: [StatementLine]
        let found: String
        switch kind {
        case .pdf:
            let (rows, pages) = try pdfRows(url, password: password)
            // The table as the eye reads it first; the plain lines are the fallback for a
            // page whose geometry says nothing.
            let byColumn = StatementLines.fromColumns(rows)
            lines = byColumn.isEmpty ? StatementLines.fromText(rows.map(\.line).joined(separator: "\n")) : byColumn
            found = "The PDF has \(pages) page\(pages == 1 ? "" : "s") of text and \(rows.count) rows, but none carried a date and an amount."
        case .csv:
            lines = StatementLines.fromCSV(try plainText(url))
            found = "The CSV has no header row naming a date, a description and an amount."
        case .text:
            let text = try plainText(url)
            let csv = StatementLines.fromCSV(text)
            lines = csv.isEmpty ? StatementLines.fromText(text) : csv
            found = "The text has no line that begins with a date and ends with an amount."
        case .xlsx:
            let records = try xlsxRecords(url)
            lines = StatementLines.fromRecords(records)
            found = "The sheet has \(records.count) rows, but no header row naming a date, a description and an amount."
        case .xls:
            let records: [[String]]
            do {
                records = try BIFFWorkbook.records(try Data(contentsOf: url))
            } catch BIFFWorkbook.ReadError.notACompoundFile {
                // Some banks name a web page or a text export ".xls"; read it for what it is.
                let text = try plainText(url)
                records = text.contains("<table") || text.contains("<TABLE") ? htmlRecords(text) : CSV.records(text.replacingOccurrences(of: "\t", with: ","))
            }
            lines = StatementLines.fromRecords(records)
            found = "The workbook has \(records.count) rows, but no header row naming a date, a description and an amount."
        }
        guard !lines.isEmpty else { throw ReadError.noLines(found) }
        return lines
    }

    // MARK: PDF

    /// Every page's words with where they sit, gathered into the rows a person sees.
    /// Text alone is not enough: PDFKit runs two printed lines together, drops the spacing
    /// that separates columns, and a table drawn cell by cell arrives out of order.
    static func pdfRows(_ url: URL, password: String?) throws -> (rows: [StatementRow], pages: Int) {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else { throw ReadError.unreadable }
        if document.isLocked {
            guard let password, !password.isEmpty else { throw ReadError.locked }
            guard document.unlock(withPassword: password) else { throw ReadError.wrongPassword }
        }
        var rows: [StatementRow] = []
        var pagesWithText = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string,
                  text.contains(where: { $0.isLetter || $0.isNumber })
            else { continue }
            pagesWithText += 1
            // An empty row marks the page's end: a narration never wraps across it.
            if !rows.isEmpty { rows.append(StatementRow(words: [])) }
            rows += rowsByPosition(on: page)
        }
        guard pagesWithText > 0 else { throw ReadError.scanned }
        return (rows, pagesWithText)
        #else
        throw ReadError.unsupported("pdf")
        #endif
    }

    #if canImport(PDFKit)
    /// The page's printed rows, each a line of words with where they sit, found the way
    /// the eye finds them: by height, then by gaps. The newlines in `page.string` are the
    /// reader's own and match no character on the page, so the text is flattened first.
    static func rowsByPosition(on page: PDFPage) -> [StatementRow] {
        // Each word of the page's text asked for its own box. The text and its boxes
        // share one index space here; the per-character boxes do not, because the text
        // carries spaces and line breaks the page never printed.
        let text = page.string ?? ""
        let whole = text as NSString
        guard let tokens = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        var words: [StatementWord] = []
        for match in tokens.matches(in: text, range: NSRange(location: 0, length: whole.length)) {
            guard let box = page.selection(for: match.range)?.bounds(for: page), box.width > 0, box.height > 0 else { continue }
            words.append(StatementWord(text: whole.substring(with: match.range), minX: box.minX, maxX: box.maxX, minY: box.minY, maxY: box.maxY))
        }
        guard !words.isEmpty else { return [] }

        // Two words share a line when their boxes mostly overlap in height; a line's
        // first word is the measure for the rest. A narration's first line printed a few
        // points above its row, as one bank does, overlaps that row by a third and stays
        // its own line.
        var rows: [[StatementWord]] = []
        for word in words.sorted(by: { $0.midY > $1.midY }) {
            if let anchor = rows.last?.first {
                let overlap = min(anchor.maxY, word.maxY) - max(anchor.minY, word.minY)
                let shorter = min(anchor.maxY - anchor.minY, word.maxY - word.minY)
                if shorter > 0, overlap >= shorter * 0.6, abs(anchor.midY - word.midY) < shorter * 0.6 {
                    rows[rows.count - 1].append(word)
                    continue
                }
            }
            rows.append([word])
        }
        return rows.map { row in
            // Pieces that touch are one word: "28,587" and the ".00" a bad font set apart.
            var joined: [StatementWord] = []
            for word in row.sorted(by: { $0.minX < $1.minX }) {
                if var last = joined.last, word.minX - last.maxX < 1.0, word.minX >= last.minX {
                    last.text += word.text
                    last.maxX = max(last.maxX, word.maxX)
                    last.minY = min(last.minY, word.minY)
                    last.maxY = max(last.maxY, word.maxY)
                    joined[joined.count - 1] = last
                } else {
                    joined.append(word)
                }
            }
            return StatementRow(words: joined)
        }
    }
    #endif

    // MARK: sheets and text

    /// A spreadsheet's rows of cells, whichever Excel it is — for sending as text.
    static func records(for url: URL) throws -> [[String]] {
        switch kind(of: url) {
        case .xlsx?:
            return try xlsxRecords(url)
        case .xls?:
            do {
                return try BIFFWorkbook.records(try Data(contentsOf: url))
            } catch BIFFWorkbook.ReadError.notACompoundFile {
                let text = try plainText(url)
                return text.contains("<table") || text.contains("<TABLE") ? htmlRecords(text) : CSV.records(text.replacingOccurrences(of: "\t", with: ","))
            }
        default:
            return CSV.records(try plainText(url))
        }
    }

    /// Every sheet's rows as records, cells by column letter; dates come out ISO.
    static func xlsxRecords(_ url: URL) throws -> [[String]] {
        guard let file = XLSXFile(filepath: url.path) else { throw ReadError.unreadable }
        let strings = try? file.parseSharedStrings()
        var records: [[String]] = []
        for workbook in try file.parseWorkbooks() {
            for entry in try file.parseWorksheetPathsAndNames(workbook: workbook) {
                let sheet = try file.parseWorksheet(at: entry.path)
                for row in sheet.data?.rows ?? [] {
                    var record: [String] = []
                    for cell in row.cells {
                        let index = columnIndex(cell.reference.column.value)
                        while record.count <= index { record.append("") }
                        // The cell's own value, never a guess at what it means: a reader
                        // that reads every number as a date turns amounts into 1904.
                        if let strings, let value = cell.stringValue(strings) {
                            record[index] = value
                        } else if let value = cell.inlineString?.text ?? cell.value {
                            record[index] = value
                        }
                    }
                    records.append(record)
                }
            }
        }
        return records
    }

    /// "A" → 0, "AB" → 27.
    static func columnIndex(_ letters: String) -> Int {
        letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    /// The rows of the first table in a web page, cells as their visible text.
    static func htmlRecords(_ html: String) -> [[String]] {
        func matches(_ pattern: String, in text: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            }
        }
        return matches(#"<tr\b[^>]*>(.*?)</tr>"#, in: html).map { row in
            matches(#"<t[dh]\b[^>]*>(.*?)</t[dh]>"#, in: row).map { cell in
                cell.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    static func plainText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .isoLatin1, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw ReadError.unreadable
    }
}
