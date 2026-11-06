// The Home Screen widget: the truest remote control, answering "what's coming?" without
// opening the app, from the same arithmetic as the desktop's menu bar.
//
// Reads the vault directly, not a cached copy — a cache would be wrong exactly when it
// mattered, after a Mac edit the phone hasn't opened since.
import LongbookCore
import SwiftUI
import UIKit
import WidgetKit

struct NextPaymentEntry: TimelineEntry {
    let date: Date
    /// nil means we genuinely couldn't read the vault; `day` nil inside means we read it fine and
    /// nothing is due. The widget says different things for those, because they're different facts.
    let day: PaymentDay?
    let unreachable: Bool
    let memberNames: [String: String]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NextPaymentEntry {
        NextPaymentEntry(date: Date(), day: nil, unreachable: false, memberNames: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (NextPaymentEntry) -> Void) {
        completion(read())
    }

    /// One entry, refreshed just after midnight — the desktop's day-rollover discipline:
    /// "today" quietly goes wrong at 00:00. WidgetKit treats the date as a request, not
    /// a promise — a floor on staleness. The app also nudges it after every load.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextPaymentEntry>) -> Void) {
        let entry = read()
        let tomorrow = LB.calendar.startOfDay(for: LB.addDays(Date(), 1))
        completion(Timeline(entries: [entry], policy: .after(tomorrow.addingTimeInterval(30))))
    }

    /// The real vault first, the app's copy second, then "unreachable". The extension holds its
    /// own iCloud entitlement, so it reads the container directly — the only way to see a Mac
    /// edit. The fallback covers a vault in the app's own folder, outside this sandbox.
    private func read() -> NextPaymentEntry {
        if let folder = VaultContainer.vaultURL(), let loaded = try? VaultReader.load(from: folder) {
            return entry(from: loaded.vault)
        }
        if let bytes = VaultMirror.read(), let vault = try? JSONDecoder().decode(Vault.self, from: bytes) {
            return entry(from: vault)
        }
        return NextPaymentEntry(date: Date(), day: nil, unreachable: true, memberNames: [:])
    }

    private func entry(from vault: Vault) -> NextPaymentEntry {
        let names = Dictionary(
            vault.familyMembers.map { ($0.id, $0.name) },
            uniquingKeysWith: { a, _ in a }
        )
        return NextPaymentEntry(
            date: Date(),
            // The next day anything is owed, so a card bill due tomorrow is never skipped.
            day: nextDueDay(vault, LB.todayMid()),
            unreachable: false,
            memberNames: names
        )
    }
}

/// The widget's three inks, kept inline: the design package is deliberately not linked into the
/// extension. Dark is the archived widget's own; light is the app's light page and text, so a
/// Home Screen in Light shows the widget as the app looks in Light.
private enum Ink {
    static let bg = pair(dark: 0x1C1C1E, light: 0xF6F4EF)    // the page
    static let ink = pair(dark: 0xEDEBE7, light: 0x26241F)   // primary text
    static let ink3 = pair(dark: 0x989796, light: 0x655F55)  // captions, still AA on the page

    private static func pair(dark: UInt, light: UInt) -> Color {
        Color(UIColor { trait in rgb(trait.userInterfaceStyle == .light ? light : dark) })
    }

    private static func rgb(_ hex: UInt) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct LongbookWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextPaymentEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("next payment")
                .font(.caption2)
                .foregroundStyle(Ink.ink3)

            if entry.unreachable {
                // Not an error the reader can fix from here, so it doesn't shout. Opening the app is
                // the whole fix (it rewrites the mirror), and that's what the line asks for.
                Text("open longbook")
                    .font(.headline)
                    .foregroundStyle(Ink.ink)
                Text("to reach your vault")
                    .font(.caption)
                    .foregroundStyle(Ink.ink3)
            } else if let day = entry.day {
                Text(LB.dayWord(day.days))
                    .font(family == .systemSmall ? .title3.weight(.semibold) : .title.weight(.semibold))
                    .foregroundStyle(Ink.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                // The total is spending only. A day holding nothing but a transfer says so
                // here, in place of a zero.
                Text(day.charges.isEmpty ? transfersWord(day) : fmtMoneyTotals(sumByCurrency(day.charges)))
                    .font(.headline)
                    .foregroundStyle(Ink.ink)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(names(day))
                    .font(.caption)
                    .foregroundStyle(Ink.ink3)
                    .lineLimit((family == .systemSmall ? 2 : 3) - (sharedDay(day) ? 1 : 0))
                if sharedDay(day) {
                    Text(transfersWord(day))
                        .font(.caption)
                        .foregroundStyle(Ink.ink3)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            } else {
                Text("nothing due")
                    .font(.headline)
                    .foregroundStyle(Ink.ink)
                Text("nothing recurring is coming up")
                    .font(.caption)
                    .foregroundStyle(Ink.ink3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// On the medium widget there's room to say whose commitment it is — the one fact the amount and
    /// the date don't carry. Names render exactly as typed; user data is never re-cased.
    private func names(_ day: PaymentDay) -> String {
        (day.charges.isEmpty ? day.transfers : day.charges)
            .map { charge in
                guard family != .systemSmall,
                      let id = charge.sub.familyMemberId,
                      let who = entry.memberNames[id]
                else { return charge.sub.name }
                return "\(charge.sub.name) · \(who)"
            }
            .joined(separator: ", ")
    }

    /// Spending and a transfer due together: the transfer takes a caption line of its own.
    private func sharedDay(_ day: PaymentDay) -> Bool {
        !day.charges.isEmpty && !day.transfers.isEmpty
    }

    /// The day's transfers in their own words, "1 transfer, ₹12,450": beside the total,
    /// never inside it.
    private func transfersWord(_ day: PaymentDay) -> String {
        "\(day.transfers.count) transfer\(day.transfers.count == 1 ? "" : "s"), "
            + fmtMoneyTotals(sumByCurrency(day.transfers))
    }
}

@main
struct LongbookWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LongbookNextPayment", provider: Provider()) { entry in
            LongbookWidgetView(entry: entry)
                // The app's page colour, not the system's material — a widget that borrowed the
                // wallpaper's tint would read as someone else's, and this one has to look like the
                // app it's a remote for.
                .containerBackground(Ink.bg, for: .widget)
        }
        .configurationDisplayName("next payment")
        .description("what's payable next, and how much.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
