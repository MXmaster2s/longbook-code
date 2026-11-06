import DesignSystem
import SwiftUI

extension View {
    /// The screen's tutorial starts the first time it opens on this device, and its card is
    /// counted as a popover over the screen while it shows.
    func screenTutorial(_ screen: ScreenTutorial) -> some View {
        modifier(ScreenTutorialModifier(screen: screen, popup: screen.popupName))
    }

    /// A part of the screen a tutorial can light; nil marks nothing. `adjust` moves the lit
    /// area off the view, for a part the system draws, such as a search bar.
    func tutorialTarget(_ target: TutorialTarget?, adjust: ((CGRect) -> CGRect)? = nil) -> some View {
        modifier(TutorialTargetModifier(target: target, adjust: adjust))
    }
}

private struct ScreenTutorialModifier: ViewModifier {
    let screen: ScreenTutorial
    let popup: StaticString

    func body(content: Content) -> some View {
        content
            .onAppear { TutorialCenter.shared.appeared(screen) }
            .onDisappear { TutorialCenter.shared.disappeared(screen) }
            .measured(popup, .popover, when: TutorialCenter.shared.active == screen)
    }
}

private struct TutorialTargetModifier: ViewModifier {
    let target: TutorialTarget?
    let adjust: ((CGRect) -> CGRect)?
    @State private var id = UUID()
    /// The last place reported: a view that goes and comes back unmoved reports no change,
    /// so it hands this in again when it reappears.
    @State private var last: CGRect?

    func body(content: Content) -> some View {
        if let target {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                    let place = adjust?(rect) ?? rect
                    last = place
                    TutorialCenter.shared.setFrame(target, id: id, rect: place)
                }
                .onAppear { if let last { TutorialCenter.shared.setFrame(target, id: id, rect: last) } }
                .onDisappear { TutorialCenter.shared.removeFrame(target, id: id) }
        } else {
            content
        }
    }
}

/// Over the whole window: the screen dimmed but for the part being explained, a ring
/// around that part, and the card beside it. The light and the card glide from part to part.
struct TutorialOverlay: View {
    private var center: TutorialCenter { TutorialCenter.shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardSize: CGSize = .zero

    /// The ring stands this far off the part it lights.
    private static let pad: CGFloat = 6
    private static let gap: CGFloat = 12
    private static let margin: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let window = geo.frame(in: .global)
            ZStack(alignment: .topLeading) {
                if let screen = center.active, center.step < center.steps.count {
                    let step = center.steps[center.step]
                    let hole = hole(for: step, in: window, size: geo.size)
                    TutorialScrim(hole: hole ?? CGRect(x: geo.size.width / 2, y: geo.size.height / 2, width: 0, height: 0))
                        .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                        // The book under the dimming waits: a tap there does nothing.
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .accessibilityHidden(true)
                    if let hole {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(LBColor.brand.color, lineWidth: 2)
                            .frame(width: hole.width, height: hole.height)
                            .offset(x: hole.minX, y: hole.minY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    TutorialCard(screen: screen, step: step, index: center.step, count: center.steps.count)
                        .frame(width: cardWidth(geo.size))
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                        .offset(cardOrigin(hole: hole, in: geo.size))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { center.canvas = $0 }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? .easeOut(duration: 0.2) : OnboardingMotion.step, value: center.step)
        .animation(.easeOut(duration: 0.25), value: center.active)
    }

    /// The lit part in the overlay's own points, padded for the ring and kept on screen.
    private func hole(for step: TutorialStep, in window: CGRect, size: CGSize) -> CGRect? {
        guard let target = step.target, let rect = center.liveFrames[target] else { return nil }
        var local = rect.offsetBy(dx: -window.minX, dy: -window.minY).insetBy(dx: -Self.pad, dy: -Self.pad)
        // A panel running on under the phone's tab bar is lit down to the bar, not over it;
        // the bar's own Add sits inside the bar and is lit there.
        let bar = size.height - Self.tabBar
        if local.minY < bar - 40, local.maxY > bar { local.size.height = bar - local.minY }
        return local.intersection(CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
    }

    /// The phone's tab bar, home indicator included; the Mac has none.
    private static var tabBar: CGFloat {
        #if os(iOS)
        92
        #else
        0
        #endif
    }

    private func cardWidth(_ size: CGSize) -> CGFloat {
        #if os(macOS)
        330
        #else
        min(size.width - 2 * Self.margin, 360)
        #endif
    }

    /// Under the lit part when there is room, else above it, else beside it, else in the
    /// middle; never off the window's edges.
    private func cardOrigin(hole: CGRect?, in size: CGSize) -> CGSize {
        let width = cardWidth(size), height = max(cardSize.height, 120)
        let top: CGFloat = 54, bottom = size.height - Self.margin
        guard let hole else {
            return CGSize(width: (size.width - width) / 2, height: (size.height - height) / 2)
        }
        let x = min(max(hole.minX, Self.margin), size.width - width - Self.margin)
        if hole.maxY + Self.gap + height <= bottom - 72 { return CGSize(width: x, height: hole.maxY + Self.gap) }
        if hole.minY - Self.gap - height >= top { return CGSize(width: x, height: hole.minY - Self.gap - height) }
        let y = min(max(hole.minY, top), bottom - height)
        if hole.maxX + Self.margin + width <= size.width - Self.margin { return CGSize(width: hole.maxX + Self.margin, height: y) }
        if hole.minX - Self.margin - width >= Self.margin { return CGSize(width: hole.minX - Self.margin - width, height: y) }
        return CGSize(width: (size.width - width) / 2, height: (size.height - height) / 2)
    }
}

/// The dimming with a rounded opening; the opening's place and size animate between steps.
private struct TutorialScrim: Shape {
    var hole: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14), style: .continuous)
        return path
    }
}

/// The card: which tutorial and how far along, what this part is, and the two ways on. It
/// wears the theme opposite the app's, so it stands out from the screen it explains.
private struct TutorialCard: View {
    let screen: ScreenTutorial
    let step: TutorialStep
    let index: Int
    let count: Int
    @Environment(\.colorScheme) private var scheme

    private var last: Bool { index == count - 1 }

    var body: some View {
        // The card glides to its next place; its words fade out and in rather than morph,
        // stacked so the old and new never push each other while they cross.
        ZStack(alignment: .topLeading) {
            content
                .id(index)
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.15)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        }
        .padding(LBSpacing.s4)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
        .environment(\.colorScheme, scheme == .dark ? .light : .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            HStack(spacing: LBSpacing.s2) {
                Text("\(screen.title) tutorial")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                Spacer(minLength: LBSpacing.s2)
                HStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { bar in
                        Capsule()
                            .fill(bar <= index ? LBColor.brand.color : LBColor.hairline.color)
                            .frame(width: 16, height: 3)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(index + 1) of \(count)")
            }
            Text(step.title)
                .lbText(.headline)
                .foregroundStyle(LBColor.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Text(last ? [step.body, screen.replayNote].compactMap { $0 }.joined(separator: " ") : step.body)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: LBSpacing.s2) {
                if !last {
                    Button {
                        Measure.used("tutorial_skip")
                        TutorialCenter.shared.finish()
                    } label: {
                        Text("Skip tutorial")
                            .lbText(.label)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .lbButtonStyle()
                    .keyboardShortcut(.cancelAction)
                }
                Spacer(minLength: LBSpacing.s2)
                Button {
                    if last {
                        Measure.used("tutorial_done")
                        TutorialCenter.shared.finish()
                    } else {
                        Measure.used("tutorial_next")
                        TutorialCenter.shared.next()
                    }
                } label: {
                    Text(last ? "Done" : "Next")
                        .lbText(.label)
                        .foregroundStyle(LBColor.onBrand.color)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background(LBColor.brand.color, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(OnboardingPressStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
