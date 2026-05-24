import Foundation
import AVFoundation

/// Centralized, minimal audio-feedback layer for Moti.
///
/// Philosophy: *quiet cognitive feedback*, not notification noise. Sounds fire
/// only at meaningful moments — a thought captured, intent understood, a plan
/// resettled, ambiguity surfaced, a task completed, a gentle failure — never on
/// ordinary taps.
///
/// Design notes:
/// - Uses `AVAudioPlayer` (AVFoundation; no third-party dependencies).
/// - Audio session category `.ambient` + `.mixWithOthers`: never grabs the
///   microphone (so it can't fight `SpeechTranscriptionService`), plays *under*
///   the user's music, and honors the hardware silent switch — exactly right
///   for subtle UI feedback.
/// - Graceful: if an audio file is missing, `play(_:)` is a silent no-op. The
///   app never crashes for a missing asset, so shipping before the sound design
///   is finished is completely safe.
/// - Anti-overlap: a short global cooldown stops rapid-fire stacking.
/// - Mutable: honors the `soundEffectsEnabled` UserDefaults flag (default on)
///   and a low default `baseVolume`, both adjustable at runtime.
///
/// ## Adding audio assets
/// Drop short (< ~1s), soft files into `Moti/Resources/Sounds/` and add them to
/// the **Moti** target (or add the folder as a *folder reference* so new files
/// are bundled automatically). Name each file after the matching `Event` raw
/// value — `capture`, `understood`, `reorganized`, `ambiguous`, `completed`,
/// `error`. Accepted extensions, in priority order: `.caf`, `.wav`, `.m4a`,
/// `.aiff`, `.mp3`. See `Moti/Resources/Sounds/README.md`.
final class SoundManager {

    static let shared = SoundManager()

    /// Cognitive moments worth a sound. The raw value is the base file name.
    enum Event: String, CaseIterable {
        case capture        // soft tactile tap — a thought is safely captured
        case understood     // airy shimmer — AI interpreted the user's intent
        case reorganized    // magnetic settle — timeline / plan resettled
        case ambiguous      // gentle suspended tone — needs clarification
        case completed      // light release — a task is done
        case error          // soft low cue — gentle failure, never harsh

        /// Per-event relative loudness, multiplied by `baseVolume`, to keep the
        /// palette balanced (errors quieter, completion a touch more present).
        var volumeScale: Float {
            switch self {
            case .capture:     return 0.90
            case .understood:  return 0.80
            case .reorganized: return 0.85
            case .ambiguous:   return 0.70
            case .completed:   return 1.00
            case .error:       return 0.65
            }
        }
    }

    /// UserDefaults key — shared with the Settings "Sound effects" toggle.
    static let enabledKey = "soundEffectsEnabled"

    /// Low by default: premium feedback sits *under* the UI, not over it.
    /// Range 0...1 (relative to system volume). Adjust at runtime, e.g.
    /// `SoundManager.shared.baseVolume = 0.5`.
    var baseVolume: Float = 0.35

    private let acceptedExtensions = ["caf", "wav", "m4a", "aiff", "mp3"]
    private let cooldown: TimeInterval = 0.08   // anti-overlap window

    private var players: [Event: AVAudioPlayer] = [:]
    private var missing: Set<Event> = []         // remember misses → no repeat bundle lookups
    private var lastPlay = Date.distantPast
    private var sessionReady = false

    private init() {}

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Preloads whatever audio is bundled so the first real event has no decode
    /// hitch. Call once at launch. Missing files are remembered and skipped.
    func prewarm() {
        runOnMain { Event.allCases.forEach { _ = self.player(for: $0) } }
    }

    /// Plays the sound for an event. Silent no-op when sounds are disabled, the
    /// file is missing, or another sound played within the cooldown window.
    /// Safe to call from any thread.
    func play(_ event: Event) {
        runOnMain { self.performPlay(event) }
    }

    // MARK: - Private

    private func performPlay(_ event: Event) {
        guard isEnabled else { return }

        let now = Date()
        guard now.timeIntervalSince(lastPlay) >= cooldown else { return }

        guard let player = player(for: event) else { return }   // graceful miss
        lastPlay = now

        configureSession()
        player.volume = max(0, min(1, baseVolume * event.volumeScale))
        player.currentTime = 0
        player.play()
    }

    private func player(for event: Event) -> AVAudioPlayer? {
        if let existing = players[event] { return existing }
        if missing.contains(event) { return nil }

        guard
            let url = url(for: event),
            let player = try? AVAudioPlayer(contentsOf: url)
        else {
            missing.insert(event)
            return nil
        }
        player.prepareToPlay()
        players[event] = player
        return player
    }

    private func url(for event: Event) -> URL? {
        for ext in acceptedExtensions {
            if let url = Bundle.main.url(forResource: event.rawValue, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    /// `.ambient` + `.mixWithOthers`: input-free (never disturbs the speech
    /// recognizer), plays beneath background audio, honors the silent switch.
    /// Set lazily on first playback so launch never touches the shared session.
    private func configureSession() {
        guard !sessionReady else { return }
        sessionReady = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
