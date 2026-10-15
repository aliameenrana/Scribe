import Foundation
import AVFoundation

@MainActor
final class PlaybackController: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var playingSegmentID: UUID?
    @Published var playbackRate: Float = 1.0 {
        didSet { player?.rate = playbackRate }
    }

    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private var player: AVAudioPlayer?
    private var displayTimer: Timer?
    private var segmentEndBoundary: Double?

    func load(url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.rate = playbackRate
        player?.prepareToPlay()
    }

    func playSegment(_ segment: TranscriptSegment) {
        guard let player else { return }
        segmentEndBoundary = segment.end
        playingSegmentID = segment.id
        player.currentTime = segment.start
        player.play()
        isPlaying = true
        startDisplayTimer()
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopDisplayTimer()
        } else {
            segmentEndBoundary = nil
            playingSegmentID = nil
            player.play()
            isPlaying = true
            startDisplayTimer()
        }
    }

    func seek(to time: Double) {
        player?.currentTime = time
        currentTime = time
        segmentEndBoundary = nil
        playingSegmentID = nil
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopDisplayTimer()
    }

    var duration: Double {
        player?.duration ?? 0
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if let boundary = self.segmentEndBoundary, player.currentTime >= boundary {
                    player.pause()
                    self.isPlaying = false
                    self.playingSegmentID = nil
                    self.stopDisplayTimer()
                }
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.playingSegmentID = nil
                    self.stopDisplayTimer()
                }
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
}
