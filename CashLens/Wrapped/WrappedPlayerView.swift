import SwiftUI

struct WrappedPlayerView: View {
    let stats: WrappedStats
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("cashlens.wrapped.includeAmountsOnShare") private var includeAmounts = false

    @State private var index = 0
    @State private var tickCount = 0
    @State private var isHolding = false
    @State private var pressStarted: Date?
    @State private var didFinish = false
    @State private var shareFailed = false

    private var pages: [WrappedPageKind] {
        WrappedScript.pages(for: stats)
    }

    var body: some View {
        ZStack {
            WrappedCardView(
                page: pages[safe: index] ?? .total,
                stats: stats,
                showAmounts: true,
                mode: .player
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topChrome
                    .padding(.top, 8)
                    .padding(.horizontal, 4)

                storySurface

                bottomChrome
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 12)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task(id: index) {
            await play()
        }
        .alert("Couldn't make the image", isPresented: $shareFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The card didn't render. Try again.")
        }
    }

    private var topChrome: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, _ in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.28))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(0, geo.size.width * fraction(for: pageIndex)))
                        }
                    }
                    .frame(height: 3)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Card \(index + 1) of \(pages.count)")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var storySurface: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(storyGesture(width: geo.size.width))
                .accessibilityElement()
                .accessibilityLabel(spokenCard)
                .accessibilityHint(reduceMotion
                    ? "Autoplay is off. Use Previous card or Next card."
                    : "Left side goes back. Right side goes forward. Hold to pause. Swipe down to close.")
                .accessibilityAction(named: Text("Previous card")) { goBack() }
                .accessibilityAction(named: Text("Next card")) { goForward(fromTap: true) }
                .accessibilityAction(named: Text("Close")) { onDismiss() }
        }
    }

    private var bottomChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            if reduceMotion {
                Text("Autoplay is off")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.white.opacity(0.75))
            }

            Toggle(isOn: $includeAmounts) {
                Text(includeAmounts ? "Amounts on the shared image" : "Amounts hidden on the shared image")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Color(red: 180 / 255, green: 140 / 255, blue: 240 / 255))

            HStack(spacing: 10) {
                Button(action: shareCurrent) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                if WrappedShareConfig.isInstagramConfigured {
                    Button(action: shareToInstagram) {
                        Label("Stories", systemImage: "camera.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share to Instagram Stories")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.38))
        )
    }

    private var spokenCard: String {
        let page = pages[safe: index] ?? .total
        let copy = WrappedCopy.content(page: page, stats: stats, showAmounts: true)
        return [copy.hero, copy.line, copy.footnote]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private func fraction(for pageIndex: Int) -> CGFloat {
        if pageIndex < index { return 1 }
        if pageIndex > index { return 0 }
        if reduceMotion || didFinish { return 1 }
        return CGFloat(tickCount) / CGFloat(WrappedScript.ticksPerCard)
    }

    private func play() async {
        guard !reduceMotion else { return }
        tickCount = 0
        didFinish = false
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if isHolding { continue }
            if didFinish { return }
            tickCount += 1
            if tickCount >= WrappedScript.ticksPerCard {
                let finished = advanceAutomatically()
                if finished { return }
            }
        }
    }

    private func storyGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { _ in
                if pressStarted == nil {
                    pressStarted = Date()
                    isHolding = true
                }
            }
            .onEnded { value in
                let started = pressStarted ?? Date()
                pressStarted = nil
                isHolding = false

                let dx = value.translation.width
                let dy = value.translation.height
                if dy > 110 && dy > abs(dx) * 1.15 {
                    onDismiss()
                    return
                }

                let moved = hypot(dx, dy)
                let duration = Date().timeIntervalSince(started)
                // A quick press with almost no travel is a tap. A longer press pauses and resumes.
                let looksLikeTap = duration < 0.25 && moved < 24 && width > 1
                guard looksLikeTap else { return }

                let x = value.startLocation.x
                let backEdge = width / 3
                let backZone = layoutDirection == .rightToLeft ? x > width - backEdge : x < backEdge
                if backZone {
                    goBack()
                } else {
                    goForward(fromTap: true)
                }
            }
    }

    private func goBack() {
        HapticManager.shared.selectionChanged()
        didFinish = false
        tickCount = 0
        if index == 0 { return }
        index -= 1
    }

    private func goForward(fromTap: Bool) {
        if fromTap {
            HapticManager.shared.selectionChanged()
        }
        if index + 1 >= pages.count {
            onDismiss()
            return
        }
        didFinish = false
        tickCount = 0
        index += 1
    }

    /// Returns true when the story should stop autoplaying.
    private func advanceAutomatically() -> Bool {
        if index + 1 >= pages.count {
            tickCount = WrappedScript.ticksPerCard
            didFinish = true
            return true
        }
        tickCount = 0
        index += 1
        return true
    }

    private func shareCurrent() {
        HapticManager.shared.lightTap()
        let page = pages[safe: index] ?? .total
        guard let url = WrappedCardRenderer.writePNG(stats: stats, page: page, showAmounts: includeAmounts) else {
            shareFailed = true
            return
        }
        SharePresenter.present(items: [url])
    }

    private func shareToInstagram() {
        HapticManager.shared.lightTap()
        let page = pages[safe: index] ?? .total
        guard let data = WrappedCardRenderer.pngData(stats: stats, page: page, showAmounts: includeAmounts) else {
            shareFailed = true
            return
        }
        if !InstagramStoriesSharer.share(png: data) {
            shareCurrent()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

struct WrappedPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        WrappedPlayerView(stats: .preview, onDismiss: {})
    }
}
