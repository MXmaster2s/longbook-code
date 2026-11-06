#if os(macOS)
import AppKit
import DesignSystem
import LongbookCore
import SwiftUI

/// What the Mac's list screens keep between visits, on this Mac and never in the vault: the row
/// each last opened, and each table's column widths.
@MainActor
@Observable
final class ScreenMemory {
    static let shared = ScreenMemory()

    /// A row asked for from outside its screen. The token tells a second ask from the first.
    struct Door: Equatable {
        let screen: String
        let row: String
        let token = UUID()
    }

    private static let rowsKey = "longbook.screens.rows"
    private static func columnsKey(_ screen: String) -> String { "longbook.columns.\(screen)" }

    private(set) var rows: RememberedRows
    /// The sidebar's starred rows ask here; the screen named takes it up and clears it.
    var door: Door?
    /// The row each showing screen has open at this moment, for the sidebar to light.
    private(set) var openRows: [String: String] = [:]
    /// Screens whose panel was closed by hand this session, which nothing reopens by itself.
    private(set) var closedByHand: Set<String> = []
    /// What stands aside while the demo longbook is up, its rows being none of the book's.
    @ObservationIgnored private var aside: RememberedRows?

    /// The picture harness reads what its arguments name and writes nothing.
    private static var persists: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT"] == nil
        #else
        true
        #endif
    }

    private init() {
        rows = Self.read(RememberedRows.self, key: Self.rowsKey) ?? RememberedRows()
    }

    func remember(_ row: String, on screen: String) {
        closedByHand.remove(screen)
        guard rows.row(on: screen) != row else { return }
        rows.remember(row, on: screen)
        saveRows()
    }

    func forget(on screen: String?) {
        guard let screen else { return }
        closedByHand.insert(screen)
        guard rows.row(on: screen) != nil else { return }
        rows.forget(on: screen)
        saveRows()
    }

    func showing(_ row: String?, on screen: String) {
        openRows[screen] = row
    }

    /// Opens a row on its screen, whether that screen is showing or about to.
    func open(_ row: String, on screen: String) {
        remember(row, on: screen)
        door = Door(screen: screen, row: row)
    }

    func beginDemo() {
        if aside == nil { aside = rows }
    }

    func endDemo() {
        if let aside { rows = aside }
        aside = nil
    }

    func columns(on screen: String) -> ColumnSets {
        Self.read(ColumnSets.self, key: Self.columnsKey(screen)) ?? ColumnSets()
    }

    func save(_ sets: ColumnSets, on screen: String) {
        guard Self.persists, aside == nil else { return }
        write(sets, key: Self.columnsKey(screen))
    }

    private func saveRows() {
        guard Self.persists, aside == nil else { return }
        write(rows, key: Self.rowsKey)
    }

    private func write(_ value: some Encodable, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: key)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let text = UserDefaults.standard.string(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: Data(text.utf8))
    }
}

extension ListFilter {
    /// The name a list's memory goes under. A list a door narrowed has none: the door names what it opens.
    var memoryKey: String? {
        guard day == nil, months.isEmpty, methodId == nil, memberId == nil, category == nil,
              commitmentId == nil, from == nil, to == nil else { return nil }
        if bookmarked { return "bookmarks" }
        switch kind {
        case .charges: return "charges"
        case .earnings: return "earnings"
        case .transfers: return "transfers"
        case nil: return scope == nil ? "commitments" : nil
        }
    }
}

extension VaultPatch.EntityKind {
    /// The name the memory of People or Accounts goes under.
    var memoryKey: String { self == .paymentMethod ? "accounts" : "members" }
}

/// One list screen's use of the memory: landing on the row it remembers, keeping the row opened
/// since, and taking up a row asked for from the sidebar. Landing is not something the person
/// did, so nothing here counts in `Measure`, and it writes only to `ScreenMemory`.
private struct RememberedRow: ViewModifier {
    let screen: String?
    @Binding var row: String?
    /// The list is there to look in, and no door has named a row of its own.
    let ready: Bool
    let holds: (String) -> Bool
    /// Clears what would keep a row asked for off the list.
    let clearing: () -> Void
    /// Brings a row just landed on into view.
    let landed: (String) -> Void
    /// Whether a row opening is the person's own and so is kept. The screen's own first pick isn't.
    let keeps: (String) -> Bool
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .onChange(of: ready, initial: true) { _, ready in
                if ready { arrive() }
            }
            .onChange(of: row, initial: true) { _, new in
                guard let screen else { return }
                ScreenMemory.shared.showing(new, on: screen)
                if let new, keeps(new) { ScreenMemory.shared.remember(new, on: screen) }
            }
            .onDisappear {
                if let screen { ScreenMemory.shared.showing(nil, on: screen) }
            }
            .onChange(of: ScreenMemory.shared.door) { _, door in
                guard let door, door.screen == screen else { return }
                ScreenMemory.shared.door = nil
                clearing()
                row = door.row
                DispatchQueue.main.async { landed(door.row) }
            }
    }

    private func arrive() {
        guard !arrived, let screen else { return }
        arrived = true
        // A row asked for by name opens whatever else is up.
        if let door = ScreenMemory.shared.door, door.screen == screen {
            ScreenMemory.shared.door = nil
            clearing()
            row = door.row
            DispatchQueue.main.async { landed(door.row) }
            return
        }
        guard row == nil, let found = ScreenMemory.shared.rows.arrival(on: screen, holds: holds) else { return }
        // The panel is simply there on landing; it slides only when something opens it.
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { row = found }
        DispatchQueue.main.async { landed(found) }
    }
}

extension View {
    func lbRemembersRow(
        on screen: String?, row: Binding<String?>, ready: Bool,
        holds: @escaping (String) -> Bool, clearing: @escaping () -> Void = {},
        keeps: @escaping (String) -> Bool = { _ in true },
        landed: @escaping (String) -> Void
    ) -> some View {
        modifier(RememberedRow(screen: screen, row: row, ready: ready, holds: holds, clearing: clearing, landed: landed, keeps: keeps))
    }

    /// `landing` names a row to bring into view, by the id its list knows it by.
    func lbLandsOnRow(_ landing: Binding<String?>) -> some View {
        modifier(LandsOnRow(landing: landing))
    }

    /// Keeps a table's column widths per screen, one set with the side panel open and one
    /// with it closed. `ideals` are the widths its columns ask for, by title. `leadTip` is the
    /// tooltip on the first column's header.
    func lbRemembersColumns(on screen: String, panelOpen: Bool, ideals: [String: CGFloat], leadTip: String? = nil) -> some View {
        background(TableColumnProbe(screen: screen, panelOpen: panelOpen, ideals: ideals, leadTip: leadTip))
    }
}

/// Brings the row a screen just landed on into view. Rows far down are only estimated until
/// the first jump has drawn them, so it jumps once more.
private struct LandsOnRow: ViewModifier {
    @Binding var landing: String?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: landing) { _, row in
                guard let row else { return }
                landing = nil
                proxy.scrollTo(row, anchor: .center)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { proxy.scrollTo(row, anchor: .center) }
            }
        }
    }
}

/// Reaches the table's own columns, for SwiftUI's `Table` has no way to set a width or hear a
/// drag. A drag is told from the table's own resizing by the header naming the column it holds.
private struct TableColumnProbe: NSViewRepresentable {
    let screen: String
    let panelOpen: Bool
    let ideals: [String: CGFloat]
    let leadTip: String?

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.update(screen: screen, panelOpen: panelOpen, ideals: ideals, leadTip: leadTip)
    }

    @MainActor
    final class Probe: NSView {
        private var screen = ""
        private var panelOpen = false
        private var ideals: [String: CGFloat] = [:]
        private var leadTip: String?
        private var sets = ColumnSets()
        private weak var table: NSTableView?
        private var watching: [NSKeyValueObservation] = []
        private var watched: [ObjectIdentifier] = []

        // It only watches: a click goes to whatever is under it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func update(screen: String, panelOpen: Bool, ideals: [String: CGFloat], leadTip: String?) {
            if screen != self.screen { sets = ScreenMemory.shared.columns(on: screen) }
            (self.screen, self.panelOpen, self.ideals, self.leadTip) = (screen, panelOpen, ideals, leadTip)
            settle()
            // The table is laid out after the first update.
            if table == nil { DispatchQueue.main.async { [weak self] in self?.settle() } }
        }

        override func layout() {
            super.layout()
            if table == nil || untouched == nil { settle() }
        }

        private func settle() {
            if table == nil { table = findTable() }
            guard let table else { return }
            if let leadTip, let lead = table.tableColumns.first, lead.headerToolTip != leadTip { lead.headerToolTip = leadTip }
            watchColumns(of: table)
            guard table.headerView?.resizedColumn == -1 else { return }
            apply(to: table)
        }

        /// Whatever table stands where this view stands: a panel's list has no header.
        private func findTable() -> NSTableView? {
            guard window != nil, let root = window?.contentView else { return nil }
            let here = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
            func search(_ view: NSView) -> NSTableView? {
                if let table = view as? NSTableView, table.headerView != nil,
                   let frame = table.enclosingScrollView?.convert(table.enclosingScrollView?.bounds ?? .zero, to: nil),
                   frame.contains(here) { return table }
                for child in view.subviews {
                    if let found = search(child) { return found }
                }
                return nil
            }
            return search(root)
        }

        private func watchColumns(of table: NSTableView) {
            let columns = table.tableColumns.map(ObjectIdentifier.init)
            guard columns != watched else { return }
            watched = columns
            watching = table.tableColumns.map { column in
                column.observe(\.width) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.columnResized() }
                }
            }
        }

        private func columnResized() {
            guard let table, table.headerView?.resizedColumn != -1 else { return }
            var widths: [String: Double] = [:]
            for column in table.tableColumns where column.minWidth != column.maxWidth {
                widths[column.headerCell.stringValue] = column.width
            }
            sets.record(widths, panelOpen: panelOpen)
            ScreenMemory.shared.save(sets, on: screen)
            table.columnAutoresizingStyle = .noColumnAutoresizing
        }

        /// The set in force, held as it is whatever the table's width. A set never dragged
        /// starts as an untouched table does, and follows the table's width from there.
        private func apply(to table: NSTableView) {
            guard let saved = sets.inForce(panelOpen: panelOpen) else {
                table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
                if untouched != panelOpen, layOutUntouched(table) { untouched = panelOpen }
                return
            }
            untouched = nil
            table.columnAutoresizingStyle = .noColumnAutoresizing
            for column in table.tableColumns {
                if let width = saved[column.headerCell.stringValue], column.width != width { column.width = width }
            }
        }

        /// Which state the untouched layout was last laid for.
        private var untouched: Bool?

        /// As the table lays out alone: each column's ideal, with what is over or short shared equally.
        private func layOutUntouched(_ table: NSTableView) -> Bool {
            let columns = table.tableColumns.filter { ideals[$0.headerCell.stringValue] != nil }
            guard !columns.isEmpty, let scroll = table.enclosingScrollView, scroll.contentView.bounds.width > 0 else { return false }
            let fixed = table.tableColumns.filter { ideals[$0.headerCell.stringValue] == nil }.reduce(0) { $0 + $1.width }
            let gaps = CGFloat(table.tableColumns.count) * table.intercellSpacing.width
            // The list's own trailing margin stands past the last column.
            let room = scroll.contentView.bounds.width - LBSpacing.s4 - fixed - gaps
            let asked = columns.reduce(0) { $0 + (ideals[$1.headerCell.stringValue] ?? 0) }
            let share = (room - asked) / CGFloat(columns.count)
            for column in columns {
                column.width = (ideals[column.headerCell.stringValue] ?? 0) + share
            }
            return true
        }
    }
}
#endif
