import DesignSystem
import SwiftUI

/// Something to do while the reading runs: coins fall, a slab under the finger fires upward, and
/// a coin a shot reaches bursts. It sits blurred until Play clears it; Pause brings the blur and
/// the module back. When the longbook is prepared it pauses itself.
struct WaitingGame: View {
    static let name = "longbook Burst"
    static let invitation = "A small game while your longbook is being prepared."
    #if os(macOS)
    static let rule = "Move the pointer to aim. It fires on its own."
    #else
    static let rule = "Slide to aim. It fires on its own."
    #endif
    /// The game's blur when it is not being played.
    private static let blur: CGFloat = 6

    /// What the screen around the game is doing, which decides what the module offers.
    enum Reading: Equatable {
        case underWay, prepared
        /// Read, but the save was refused; the words say why.
        case notSaved(String)
    }

    let reading: Reading
    /// Set once Play is pressed: a game never played lets the steps open by themselves.
    @Binding var played: Bool
    let onContinue: () -> Void
    let onTryAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var game = CoinGame()
    @State private var playing = false
    /// The module rises two seconds in, never at once.
    @State private var moduleDue = false

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if playing { scoreRow }
            GeometryReader { geo in
                canvas
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { drag in
                            guard playing else { return }
                            game.slab = min(max((drag.location.x - CoinGame.slabWidth / 2) / max(1, geo.size.width - CoinGame.slabWidth), 0), 1)
                        }
                    )
                    #if os(macOS)
                    .onContinuousHover { phase in
                        guard playing, case .active(let point) = phase else { return }
                        game.slab = min(max((point.x - CoinGame.slabWidth / 2) / max(1, geo.size.width - CoinGame.slabWidth), 0), 1)
                    }
                    #endif
                    .blur(radius: playing ? 0 : Self.blur)
                    .onDisappear { game.stop() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .overlay {
                if !playing, moduleShown {
                    module
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: LBSpacing.s3)))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(playing
                ? "\(Self.name): slide the slab under the coins; it fires on its own. Score \(game.score)."
                : "\(Self.name), a small game to play while your longbook is being prepared.")
        }
        .animation(LBMotion.rise(reduceMotion: reduceMotion), value: moduleShown)
        .task {
            try? await Task.sleep(for: .seconds(2))
            moduleDue = true
        }
        .onChange(of: reading) { _, now in
            if now != .underWay { pause() }
        }
    }

    private var moduleShown: Bool { moduleDue || played || reading != .underWay }

    private var canvas: some View {
        Canvas { context, size in
            let mark = context.resolve(Image("SidebarMark"))
            let slab = CGRect(x: (size.width - CoinGame.slabWidth) * game.slab, y: size.height - 16,
                              width: CoinGame.slabWidth, height: 8)
            context.fill(Path(roundedRect: slab, cornerRadius: 4), with: .color(LBColor.textSecondary.color))
            for shot in game.shots {
                let rect = CGRect(x: shot.x * size.width - 1.5, y: shot.y * size.height - 6, width: 3, height: 12)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(LBColor.brandText.color))
            }
            for coin in game.coins {
                let center = CGPoint(x: coin.x * size.width, y: coin.y * size.height)
                context.draw(mark, in: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
            }
            for burst in game.bursts {
                let radius = 8 + burst.age * 60
                let rect = CGRect(x: burst.x * size.width - radius, y: burst.y * size.height - radius,
                                  width: radius * 2, height: radius * 2)
                // Typed on its own line: Xcode 16.4 cannot pick the CGFloat to Double conversion inline.
                let fade: Double = Double(max(0, 1 - burst.age * 3))
                context.stroke(Path(ellipseIn: rect), with: .color(LBColor.brand.color.opacity(fade)), lineWidth: 2)
            }
        }
    }

    private var scoreRow: some View {
        HStack(spacing: LBSpacing.s3) {
            Text(Self.rule)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .lineLimit(1)
            Spacer(minLength: LBSpacing.s2)
            Text("Score \(game.score)")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .monospacedDigit()
            Button {
                Measure.used("pause_game")
                pause()
            } label: {
                Label("Pause", systemImage: "pause.fill")
                    .labelStyle(.iconOnly)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .frame(width: 30, height: 30)
                    .background(LBColor.chrome.color, in: Circle())
                    .contentShape(Circle())
            }
            .lbButtonStyle(.capsule)
            .help("Pause")
        }
    }

    /// Over the blurred game: its name, a line, and one action.
    private var module: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            Text(moduleTitle)
                .lbText(.headline)
                .foregroundStyle(LBColor.textPrimary.color)
            Text(moduleLine)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            moduleAction
                .padding(.top, LBSpacing.s3)
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: 320, alignment: .leading)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
        .padding(LBSpacing.s4)
    }

    private var moduleTitle: String {
        if case .notSaved = reading { return "Not saved" }
        return Self.name
    }

    private var moduleLine: String {
        switch reading {
        case .underWay: Self.invitation
        case .prepared: "Your longbook is prepared. Score \(game.score)."
        case .notSaved(let why): why
        }
    }

    @ViewBuilder
    private var moduleAction: some View {
        switch reading {
        case .underWay:
            ImportPrimaryButton(title: "Play", measure: "play", action: play)
        case .prepared:
            ImportPrimaryButton(title: "Continue", measure: "continue_prepared", action: onContinue)
            .keyboardShortcut(.defaultAction)
        case .notSaved:
            ImportPrimaryButton(title: "Try Again", measure: "try_saving_again", action: onTryAgain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func play() {
        played = true
        playing = true
        game.start()
        LBHaptics.tap()
    }

    private func pause() {
        playing = false
        game.stop()
    }
}

/// The world: coins with a place and a fall, shots with a rise, bursts with an age, a
/// slab with a place, a score. Ticks thirty times a second while a screen shows it.
@MainActor
final class CoinGame: ObservableObject {
    struct Coin: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var speed: CGFloat
    }

    struct Shot: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
    }

    struct Burst: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        var age: CGFloat
    }

    static let slabWidth: CGFloat = 56

    /// A few coins already falling, so the still before Play shows what the game is.
    @Published var coins: [Coin] = [Coin(x: 0.22, y: 0.18, speed: 0.2), Coin(x: 0.58, y: 0.34, speed: 0.22),
                                    Coin(x: 0.8, y: 0.12, speed: 0.18), Coin(x: 0.4, y: 0.6, speed: 0.24)]
    @Published var shots: [Shot] = []
    @Published var bursts: [Burst] = []
    @Published var slab: CGFloat = 0.5
    @Published var score = 0

    private var ticker: Timer?
    private var sinceCoin: TimeInterval = 0
    private var sinceShot: TimeInterval = 0

    func start() {
        guard ticker == nil else { return }
        // Added in the common modes: a plain scheduled timer stops while the Mac tracks a
        // mouse button, which read as the game pausing on every click.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(1.0 / 30.0) }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick(_ dt: TimeInterval) {
        sinceCoin += dt
        sinceShot += dt
        if sinceCoin > 1.1 {
            sinceCoin = 0
            coins.append(Coin(x: CGFloat.random(in: 0.06...0.94), y: -0.05, speed: CGFloat.random(in: 0.16...0.26)))
        }
        // The slab's centre, as a share of the width the coins fall across.
        let muzzle = 0.05 + slab * 0.90
        if sinceShot > 0.35 {
            sinceShot = 0
            shots.append(Shot(x: muzzle, y: 0.93))
        }
        var risen: [Shot] = []
        for var shot in shots {
            shot.y -= 1.1 * dt
            if shot.y > -0.05 { risen.append(shot) }
        }
        var fallen: [Coin] = []
        for var coin in coins {
            coin.y += coin.speed * dt
            if let hit = risen.firstIndex(where: { abs($0.x - coin.x) < 0.035 && abs($0.y - coin.y) < 0.05 }) {
                risen.remove(at: hit)
                bursts.append(Burst(x: coin.x, y: coin.y, age: 0))
                score += 1
                continue
            }
            if coin.y < 1.05 { fallen.append(coin) }
        }
        coins = fallen
        shots = risen
        bursts = bursts.compactMap { burst in
            var next = burst
            next.age += dt
            return next.age < 0.35 ? next : nil
        }
    }
}
