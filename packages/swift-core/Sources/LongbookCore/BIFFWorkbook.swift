// Reads the .xls a bank exports — Excel's binary workbook inside a compound file — into
// rows of cells. Our own, because no permissive library reads the format: exactly the
// records a statement needs, and every offset checked before it is read.
import Foundation

enum BIFFWorkbook {
    enum ReadError: Error, Equatable { case notACompoundFile, noWorkbook, malformed }

    /// Every sheet's rows top to bottom, cells as text: numbers in their shortest form,
    /// date-formatted cells as YYYY-MM-DD, everything else as written.
    static func records(_ data: Data) throws -> [[String]] {
        let file = try CompoundFile(data)
        guard let stream = file.stream(named: "Workbook") ?? file.stream(named: "Book") else { throw ReadError.noWorkbook }
        var parser = Parser(stream)
        return try parser.records()
    }

    // MARK: - the container

    /// The compound file: a header, a FAT of sector chains, a directory of streams, and
    /// small streams packed into a mini stream with a FAT of their own.
    struct CompoundFile {
        private let bytes: [UInt8]
        private let sectorSize: Int
        private let miniSectorSize: Int
        private let miniCutoff: Int
        private var fat: [UInt32] = []
        private var miniFat: [UInt32] = []
        private var directory: [UInt8] = []
        private var miniStream: [UInt8] = []

        init(_ data: Data) throws {
            let b = [UInt8](data)
            guard b.count >= 512, Array(b[0..<8]) == [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] else {
                throw ReadError.notACompoundFile
            }
            bytes = b
            sectorSize = 1 << Int(BIFFWorkbook.u16(b, 30))
            miniSectorSize = 1 << Int(BIFFWorkbook.u16(b, 32))
            miniCutoff = Int(BIFFWorkbook.u32(b, 56))
            guard (512...4096).contains(sectorSize), miniSectorSize == 64 else { throw ReadError.malformed }

            var fatSectors: [UInt32] = (0..<109).map { u32(76 + $0 * 4) }.filter { $0 < 0xFFFF_FFFE }
            var difat = u32(68)
            var hops = 0
            while difat < 0xFFFF_FFFE, hops < Int(u32(72)) + 1 {
                let at = offset(of: difat)
                for slot in 0..<(sectorSize / 4 - 1) {
                    let sector = u32(at + slot * 4)
                    if sector < 0xFFFF_FFFE { fatSectors.append(sector) }
                }
                difat = u32(at + sectorSize - 4)
                hops += 1
            }
            for sector in fatSectors.prefix(Int(u32(44))) {
                let at = offset(of: sector)
                for slot in 0..<(sectorSize / 4) { fat.append(u32(at + slot * 4)) }
            }

            directory = read(chain(from: u32(48), in: fat, sectorSize: sectorSize))
            guard directory.count >= 128 else { throw ReadError.malformed }

            var mini = u32(60)
            hops = 0
            while mini < 0xFFFF_FFFE, hops < Int(u32(64)) {
                let at = offset(of: mini)
                for slot in 0..<(sectorSize / 4) { miniFat.append(u32(at + slot * 4)) }
                mini = mini < fat.count ? fat[Int(mini)] : 0xFFFF_FFFE
                hops += 1
            }
            // The root entry's own stream is where every small stream lives.
            let rootStart = u32(directory, 116)
            let rootSize = Int(u32(directory, 120))
            miniStream = Array(read(chain(from: rootStart, in: fat, sectorSize: sectorSize)).prefix(rootSize))
        }

        /// The bytes of the stream with this name, or nil when the directory has no such stream.
        func stream(named name: String) -> Data? {
            var entry = 0
            while (entry + 1) * 128 <= directory.count {
                let base = entry * 128
                entry += 1
                let nameLength = Int(u16(directory, base + 64))
                guard directory[base + 66] == 2, nameLength >= 2, nameLength <= 64 else { continue }
                let nameBytes = directory[(base)..<(base + nameLength - 2)]
                guard let found = String(bytes: nameBytes, encoding: .utf16LittleEndian), found == name else { continue }
                let start = u32(directory, base + 116)
                let size = Int(u32(directory, base + 120))
                if size < miniCutoff {
                    let chain = chain(from: start, in: miniFat, sectorSize: miniSectorSize)
                    var out: [UInt8] = []
                    for sector in chain {
                        let at = Int(sector) * miniSectorSize
                        guard at + miniSectorSize <= miniStream.count else { break }
                        out += miniStream[at..<(at + miniSectorSize)]
                    }
                    return Data(out.prefix(size))
                }
                return Data(read(chain(from: start, in: fat, sectorSize: sectorSize)).prefix(size))
            }
            return nil
        }

        private func offset(of sector: UInt32) -> Int { (Int(sector) + 1) * sectorSize }

        /// The sectors of one chain, stopped at the end mark or at any loop.
        private func chain(from start: UInt32, in table: [UInt32], sectorSize: Int) -> [UInt32] {
            var out: [UInt32] = []
            var seen = Set<UInt32>()
            var sector = start
            while sector < 0xFFFF_FFFE, Int(sector) < table.count, seen.insert(sector).inserted {
                out.append(sector)
                sector = table[Int(sector)]
            }
            return out
        }

        private func read(_ chain: [UInt32]) -> [UInt8] {
            var out: [UInt8] = []
            for sector in chain {
                let at = offset(of: sector)
                guard at + sectorSize <= bytes.count else { break }
                out += bytes[at..<(at + sectorSize)]
            }
            return out
        }

        private func u16(_ at: Int) -> UInt16 { BIFFWorkbook.u16(bytes, at) }
        private func u32(_ at: Int) -> UInt32 { BIFFWorkbook.u32(bytes, at) }
        private func u16(_ b: [UInt8], _ at: Int) -> UInt16 { BIFFWorkbook.u16(b, at) }
        private func u32(_ b: [UInt8], _ at: Int) -> UInt32 { BIFFWorkbook.u32(b, at) }
    }

    static func u16(_ b: [UInt8], _ at: Int) -> UInt16 {
        guard at >= 0, at + 2 <= b.count else { return 0 }
        return UInt16(b[at]) | UInt16(b[at + 1]) << 8
    }

    static func u32(_ b: [UInt8], _ at: Int) -> UInt32 {
        guard at >= 0, at + 4 <= b.count else { return 0 }
        return UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }

    // MARK: - the records

    /// Walks the workbook stream: the shared strings, the number formats, the sheets'
    /// cells. A record the statement never needs is stepped over by its length.
    struct Parser {
        private let bytes: [UInt8]
        private var sharedStrings: [String] = []
        private var formats: [UInt16: String] = [:]
        private var xfFormats: [UInt16] = []
        private var sheetStarts: [Int] = []
        private var biff8 = true
        private var dates1904 = false

        init(_ data: Data) {
            bytes = [UInt8](data)
        }

        mutating func records() throws -> [[String]] {
            try readGlobals()
            var out: [[String]] = []
            for start in sheetStarts { out += try readSheet(at: start) }
            return out
        }

        /// A record's type, its data, and where the next one starts.
        private func record(at position: Int) -> (type: UInt16, data: ArraySlice<UInt8>, next: Int)? {
            guard position + 4 <= bytes.count else { return nil }
            let type = u16(bytes, position)
            let length = Int(u16(bytes, position + 2))
            guard position + 4 + length <= bytes.count else { return nil }
            return (type, bytes[(position + 4)..<(position + 4 + length)], position + 4 + length)
        }

        private mutating func readGlobals() throws {
            var position = 0
            var sawBOF = false
            while let (type, data, next) = record(at: position) {
                switch type {
                case 0x0809:
                    if sawBOF { return }
                    sawBOF = true
                    biff8 = u16(Array(data), 0) >= 0x0600
                case 0x000A:
                    return
                case 0x0022:
                    dates1904 = u16(Array(data), 0) == 1
                case 0x0085:
                    sheetStarts.append(Int(u32(Array(data), 0)))
                case 0x041E:
                    let d = Array(data)
                    formats[u16(d, 0)] = biff8 ? unicodeString(d, at: 2).text : byteString(d, at: 2, lengthBytes: 1)
                case 0x00E0:
                    xfFormats.append(u16(Array(data), 2))
                case 0x00FC:
                    var pieces: [ArraySlice<UInt8>] = [data]
                    var after = next
                    while let (kind, more, following) = record(at: after), kind == 0x003C {
                        pieces.append(more)
                        after = following
                    }
                    sharedStrings = sharedStringTable(pieces)
                    position = after
                    continue
                default:
                    break
                }
                position = next
            }
            guard sawBOF else { throw ReadError.malformed }
        }

        private func readSheet(at start: Int) throws -> [[String]] {
            var cells: [Int: [Int: String]] = [:]
            var position = start
            var pendingFormula: (row: Int, col: Int)?
            guard let (first, _, _) = record(at: position), first == 0x0809 else { return [] }
            while let (type, slice, next) = record(at: position) {
                let d = Array(slice)
                switch type {
                case 0x000A:
                    return rows(from: cells)
                case 0x00FD:
                    let index = Int(u32(d, 6))
                    if index < sharedStrings.count { cells[Int(u16(d, 0)), default: [:]][Int(u16(d, 2))] = sharedStrings[index] }
                case 0x0204:
                    let text = biff8 ? unicodeString(d, at: 6).text : byteString(d, at: 6, lengthBytes: 2)
                    cells[Int(u16(d, 0)), default: [:]][Int(u16(d, 2))] = text
                case 0x00D6:
                    cells[Int(u16(d, 0)), default: [:]][Int(u16(d, 2))] = byteString(d, at: 6, lengthBytes: 2)
                case 0x0203:
                    cells[Int(u16(d, 0)), default: [:]][Int(u16(d, 2))] = text(double(d, 6), xf: u16(d, 4))
                case 0x027E:
                    cells[Int(u16(d, 0)), default: [:]][Int(u16(d, 2))] = text(rk(u32(d, 6)), xf: u16(d, 4))
                case 0x00BD:
                    let row = Int(u16(d, 0))
                    let firstCol = Int(u16(d, 2))
                    var at = 4
                    var col = firstCol
                    while at + 6 <= d.count - 2 {
                        cells[row, default: [:]][col] = text(rk(u32(d, at + 2)), xf: u16(d, at))
                        at += 6
                        col += 1
                    }
                case 0x0006:
                    let row = Int(u16(d, 0)), col = Int(u16(d, 2))
                    if u16(d, 12) == 0xFFFF {
                        if d.count > 6, d[6] == 0 { pendingFormula = (row, col) }
                    } else {
                        cells[row, default: [:]][col] = text(double(d, 6), xf: u16(d, 4))
                    }
                case 0x0207:
                    if let cell = pendingFormula {
                        cells[cell.row, default: [:]][cell.col] = biff8 ? unicodeString(d, at: 0).text : byteString(d, at: 0, lengthBytes: 2)
                        pendingFormula = nil
                    }
                default:
                    break
                }
                position = next
            }
            return rows(from: cells)
        }

        private func rows(from cells: [Int: [Int: String]]) -> [[String]] {
            cells.keys.sorted().map { row in
                let line = cells[row] ?? [:]
                let width = (line.keys.max() ?? -1) + 1
                return (0..<width).map { line[$0] ?? "" }
            }
        }

        // MARK: values

        private func text(_ value: Double, xf: UInt16) -> String {
            if isDate(xf: xf) {
                let days = value + (dates1904 ? 1462 : 0)
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: Date(timeIntervalSince1970: (days - 25_569) * 86_400))
            }
            if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 4
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }

        /// Excel's own date formats by number, or a custom one that spells a day and a year.
        private func isDate(xf: UInt16) -> Bool {
            guard Int(xf) < xfFormats.count else { return false }
            let format = xfFormats[Int(xf)]
            if (14...22).contains(format) || (27...36).contains(format) || (45...47).contains(format) || (50...58).contains(format) {
                return true
            }
            guard let custom = formats[format]?.lowercased() else { return false }
            let bare = custom.replacingOccurrences(of: #"\[[^\]]*\]|"[^"]*""#, with: "", options: .regularExpression)
            return bare.contains("d") && (bare.contains("y") || bare.contains("m")) && !bare.contains("0.0")
        }

        private func double(_ d: [UInt8], _ at: Int) -> Double {
            guard at + 8 <= d.count else { return 0 }
            var bits: UInt64 = 0
            for i in 0..<8 { bits |= UInt64(d[at + i]) << (8 * UInt64(i)) }
            return Double(bitPattern: bits)
        }

        /// An RK number: a 30-bit integer or the top of a double, halved a hundred times
        /// when the low bit says so.
        private func rk(_ raw: UInt32) -> Double {
            var value: Double
            if raw & 0x02 != 0 {
                value = Double(Int32(bitPattern: raw) >> 2)
            } else {
                value = Double(bitPattern: UInt64(raw & 0xFFFF_FFFC) << 32)
            }
            if raw & 0x01 != 0 { value /= 100 }
            return value
        }

        // MARK: strings

        private func byteString(_ d: [UInt8], at: Int, lengthBytes: Int) -> String {
            let length = lengthBytes == 1 ? Int(d.count > at ? d[at] : 0) : Int(u16(d, at))
            let start = at + lengthBytes
            guard start + length <= d.count else { return "" }
            return String(bytes: d[start..<(start + length)], encoding: .windowsCP1252) ?? ""
        }

        /// A BIFF8 string in one record: a length, an options byte, the characters in one
        /// or two bytes each, and the rich-text and Asian runs it may trail.
        private func unicodeString(_ d: [UInt8], at: Int) -> (text: String, end: Int) {
            let count = Int(u16(d, at))
            guard at + 3 <= d.count else { return ("", d.count) }
            let flags = d[at + 2]
            var cursor = at + 3
            let runs = flags & 0x08 != 0 ? Int(u16(d, cursor)) : 0
            if flags & 0x08 != 0 { cursor += 2 }
            let ext = flags & 0x04 != 0 ? Int(u32(d, cursor)) : 0
            if flags & 0x04 != 0 { cursor += 4 }
            let wide = flags & 0x01 != 0
            let width = wide ? 2 : 1
            guard cursor + count * width <= d.count else { return ("", d.count) }
            let chars = d[cursor..<(cursor + count * width)]
            let text = wide
                ? (String(bytes: chars, encoding: .utf16LittleEndian) ?? "")
                : (String(bytes: chars, encoding: .windowsCP1252) ?? "")
            return (text, cursor + count * width + runs * 4 + ext)
        }

        /// The shared string table, which may run across CONTINUE records; a string cut at
        /// a record boundary resumes with a fresh options byte.
        private func sharedStringTable(_ pieces: [ArraySlice<UInt8>]) -> [String] {
            let segments = pieces.map(Array.init)
            var segment = 0
            var cursor = 8
            var out: [String] = []
            let unique = Int(BIFFWorkbook.u32(segments[0], 4))

            func available() -> Int { segments[segment].count - cursor }
            func advance() -> Bool {
                guard segment + 1 < segments.count else { return false }
                segment += 1
                cursor = 0
                return true
            }
            func byte() -> UInt8? {
                while available() <= 0 { guard advance() else { return nil } }
                defer { cursor += 1 }
                return segments[segment][cursor]
            }
            func u16() -> Int? {
                guard let a = byte(), let b = byte() else { return nil }
                return Int(a) | Int(b) << 8
            }
            func u32() -> Int? {
                guard let a = u16(), let b = u16() else { return nil }
                return a | b << 16
            }
            func skip(_ n: Int) -> Bool {
                var left = n
                while left > 0 {
                    while available() <= 0 { guard advance() else { return false } }
                    let take = min(left, available())
                    cursor += take
                    left -= take
                }
                return true
            }

            for _ in 0..<unique {
                guard let count = u16(), let flags = byte() else { break }
                let runs = flags & 0x08 != 0 ? (u16() ?? 0) : 0
                let ext = flags & 0x04 != 0 ? (u32() ?? 0) : 0
                var wide = flags & 0x01 != 0
                var scalars: [UInt8] = []
                var text = ""
                var left = count
                while left > 0 {
                    if available() <= 0 {
                        // Across a boundary the string restarts with its own width flag.
                        text += decode(scalars, wide: wide)
                        scalars = []
                        guard advance(), let again = byte() else { break }
                        wide = again & 0x01 != 0
                    }
                    let chars = min(left, available() / (wide ? 2 : 1))
                    guard chars > 0 else { guard advance() else { break }; continue }
                    scalars += segments[segment][cursor..<(cursor + chars * (wide ? 2 : 1))]
                    cursor += chars * (wide ? 2 : 1)
                    left -= chars
                }
                text += decode(scalars, wide: wide)
                out.append(text)
                guard skip(runs * 4 + ext) else { break }
            }
            return out
        }

        private func decode(_ scalars: [UInt8], wide: Bool) -> String {
            wide
                ? (String(bytes: scalars, encoding: .utf16LittleEndian) ?? "")
                : (String(bytes: scalars, encoding: .windowsCP1252) ?? "")
        }
    }
}
