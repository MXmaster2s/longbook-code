// A capped text field's edit, kept as far as the cap allows without cutting text it held.
import Foundation

public enum TextFit {
    /// The edit from `old` to `new`, as far as `cap` allows, and never below `old`'s length.
    /// The held text comes back whole, in its own characters; only what was typed or pasted
    /// is shortened to fit.
    public static func fitted(_ new: String, replacing old: String, cap: Int) -> String {
        let limit = max(cap, old.count)
        guard new.count > limit else { return new }
        let fresh = Array(new), held = Array(old)
        let room = limit - held.count
        // A paste at the end, or at the start, is settled before any match: an added run that
        // ends like the note, or repeats it, is never taken for the note's own text.
        if fresh.starts(with: held) {
            return String(held + fresh[held.count...].prefix(room))
        }
        if fresh.count >= held.count, Array(fresh.suffix(held.count)) == held {
            return String(fresh[..<(fresh.count - held.count)].prefix(room) + held)
        }
        // An edit inside the note: the end first, since a paste's opening characters can repeat
        // the held text after it, then the start.
        var back = 0
        while back < held.count, back < fresh.count,
              fresh[fresh.count - 1 - back] == held[held.count - 1 - back] { back += 1 }
        var front = 0
        while front < held.count - back, front < fresh.count - back, fresh[front] == held[front] { front += 1 }
        let inserted = fresh[front..<(fresh.count - back)].prefix(max(0, limit - front - back))
        return String(held[..<front] + inserted + held[(held.count - back)...])
    }
}
