import DesignSystem
import SwiftUI

/// Something to do while the server reads: coins fall, a slab under the finger fires
/// upward, and a coin a shot reaches bursts. Before Play it shows a still of itself with
/// its name and rule; a small button pauses it. Gone once the reading is done.
struct WaitingGame: View {
    static let name = "longbook Burst"
    #if os(macOS)
    static let rule = "Move the pointer to aim. It fires on its own."
    #else
    static let rule = "Slide to aim. It fires on its own."
    #endif

    @StateObject private var game = CoinGame()
    @State private var started = false
    @State private var paused = false

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if started {
                HStack {
                    Text(Self.rule)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                    Spacer()
                    Text("Score \(game.score)")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .monospacedDigit()
                }
            }
            GeometryReader { geo in
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
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        guard started, !paused else { return }
                        game.slab = min(max((drag.location.x - CoinGame.slabWidth / 2) / max(1, geo.size.width - CoinGame.slabWidth), 0), 1)
                    }
                )
                #if os(macOS)
                .onContinuousHover { phase in
                    guard started, !paused, case .active(let point) = phase else { return }
                    game.slab = min(max((point.x - CoinGame.slabWidth / 2) / max(1, geo.size.width - CoinGame.slabWidth), 0), 1)
                }
                #endif
                .opacity(started ? 1 : 0.5)
                .overlay {
                    if !started { startCover }
                }
                .overlay(alignment: .bottomTrailing) {
                    if started { pauseButton }
                }
                .onDisappear { game.stop() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
            .accessibilityLabel(started
                ? "\(Self.name): slide the slab under the coins; it fires on its own. Score \(game.score)."
                : "\(Self.name), a small game to play while you wait.")
        }
    }

    /// Over the still before the first touch: the game's name, its rule, and Play.
    private var startCover: some View {
        VStack(spacing: LBSpacing.s2) {
            Text(Self.name)
                .lbText(.headline)
                .foregroundStyle(LBColor.textPrimary.color)
            Text(Self.rule)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
            Button {
                Measure.used("play")
                started = true
                paused = false
                game.start()
                LBHaptics.tap()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .lbText(.label)
                    .foregroundStyle(LBColor.onBrand.color)
                    .padding(.horizontal, LBSpacing.s4)
                    .frame(minHeight: 36)
                    .background(LBColor.brand.color, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, LBSpacing.s1)
        }
        .padding(LBSpacing.s4)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
    }

    private var pauseButton: some View {
        Button {
            Measure.used("play_fill")
            paused.toggle()
            if paused { game.stop() } else { game.start() }
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LBColor.textPrimary.color)
                .frame(width: 30, height: 30)
                .background(LBColor.chrome.color, in: Circle())
                .padding(LBSpacing.s2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(paused ? "Continue the game" : "Pause the game")
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
