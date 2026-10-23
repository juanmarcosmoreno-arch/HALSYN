import AVFoundation
import HalsynCore
import SwiftUI
import UIKit

/// Animación de apertura: completa, breve o desactivada (Perfil › Apariencia).
enum IntroPreference: String, CaseIterable, Identifiable {
    case brief
    case full
    case off

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .brief: "Breve"
        case .full: "Completa"
        case .off: "Desactivada"
        }
    }

    /// Tramo del video (segundos) que se reproduce.
    var segment: ClosedRange<Double>? {
        switch self {
        case .full: 0...9.0
        // Desde que el símbolo termina de formarse hasta el nombre con el lema.
        case .brief: 2.6...6.8
        case .off: nil
        }
    }
}

/// Video de apertura en claro u oscuro según la apariencia de la app.
/// Se salta con un toque; el sonido respeta el modo silencio y no corta la música.
struct IntroVideoView: View {
    let preference: IntroPreference
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showsSkipHint = false

    /// Color del fondo de cada video, para extender el lienzo sin costuras.
    private var background: Color {
        colorScheme == .dark ? .black : Color(red: 246 / 255, green: 247 / 255, blue: 244 / 255)
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if let url = Bundle.main.url(forResource: colorScheme == .dark ? "intro-dark" : "intro-light", withExtension: "mp4"),
               let segment = preference.segment {
                IntroPlayerView(url: url, segment: segment, onFinish: onFinish)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    // Funde los bordes del video con el fondo (el viñeteado del video varía un poco).
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.18),
                            .init(color: .black, location: 0.82),
                            .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .accessibilityHidden(true)
            }
            VStack {
                Spacer()
                Text("Toca para saltar")
                    .font(.caption)
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.45))
                    .opacity(showsSkipHint ? 1 : 0)
                    .padding(.bottom, 24)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: HalsynBrand.name))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Toca para saltar"))
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeIn(duration: 0.4)) { showsSkipHint = true }
        }
    }
}

/// `AVPlayerLayer` sin controles que reproduce un tramo del video una vez.
private struct IntroPlayerView: UIViewRepresentable {
    let url: URL
    let segment: ClosedRange<Double>
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIView(context: Context) -> PlayerView {
        // Ambiental: obedece al interruptor de silencio y se mezcla con otra música.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let item = AVPlayerItem(url: url)
        let timescale = CMTimeScale(600)
        item.forwardPlaybackEndTime = CMTime(seconds: segment.upperBound, preferredTimescale: timescale)
        let player = AVPlayer(playerItem: item)
        player.isMuted = false
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        context.coordinator.observe(item)
        player.seek(to: CMTime(seconds: segment.lowerBound, preferredTimescale: timescale), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
        }
        context.coordinator.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        coordinator.stop()
    }

    final class Coordinator {
        let onFinish: () -> Void
        var player: AVPlayer?
        private var token: NSObjectProtocol?
        private var fallback: Task<Void, Never>?

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func observe(_ item: AVPlayerItem) {
            token = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                self?.finish()
            }
            // Si el video no puede reproducirse, la app no se queda esperando.
            fallback = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(11))
                self?.finish()
            }
        }

        private var finished = false

        private func finish() {
            guard !finished else { return }
            finished = true
            onFinish()
        }

        func stop() {
            fallback?.cancel()
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}

final class PlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
