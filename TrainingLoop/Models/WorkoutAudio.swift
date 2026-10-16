import AVFoundation
import AudioToolbox
import TrainingLoopCore
import UIKit

/// Signals, voice and vibration at the end of a rest (SPEC D5; TECH T6, T7). Adapted from SetLoop.
///
/// The audio session is active only during a rest: the engine running then keeps the app alive on the
/// lock screen to play the 3-2-1 and the end. Between rests nothing plays and the app may be frozen
/// (no idle silence, App Review 2.5.4). Other apps' audio is ducked only around signals.
@MainActor
final class WorkoutAudio {
    private let settings: AppSettings
    private let session = AVAudioSession.sharedInstance()
    /// Recreated with its players after the media services reset.
    private var engine = AVAudioEngine()
    /// Ticks and the end signal overlap: a tick must not cut the signal's tail.
    private var tickPlayer = AVAudioPlayerNode()
    private var signalPlayer = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)!
    private let speech = AVSpeechSynthesizer()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var players: [AVAudioPlayerNode] { [tickPlayer, signalPlayer] }
    private var observers: [NSObjectProtocol] = []

    private var isActive = false
    private var isDucked = false
    private var unduckTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        connectPlayers()
        observe()
    }

    // MARK: - Rest

    /// A rest started or resumed. Without sound and voice nothing is played, not even silence;
    /// vibration alone needs no session.
    func begin() {
        cancelRelease()
        guard settings.soundSet != nil || settings.voicePrompts else { return end() }
        guard !isActive else { return }
        isActive = true
        configure(ducked: false)
        // Rendering takes a moment; do it before the first signal, not on it.
        if let set = settings.soundSet { SoundCue.allCases.forEach { _ = buffer($0, set) } }
    }

    /// The rest was skipped or paused: release the audio at once.
    func end() {
        cancelRelease()
        unduckTask?.cancel()
        guard isActive else { return }
        isActive = false
        speech.stopSpeaking(at: .immediate)
        release()
    }

    /// "3-2-1": spoken when the voice is on, otherwise a tick.
    func countdown(_ secondsLeft: Int) {
        vibrate(strong: false)
        if settings.voicePrompts {
            speak(String(secondsLeft))
        } else {
            play(.countdown)
        }
    }

    /// The end signal and "Rest is over", then the audio is released.
    func restEnded() {
        vibrate(strong: true)
        let signal = play(.restEnd)
        speak(String(localized: "Rest is over"), after: signal)
        releaseLater(after: signal + (settings.voicePrompts ? 2 : 0))
    }

    /// "Finish": the final run, if the app is in front to play it.
    func finished() {
        guard settings.soundSet != nil else { return }
        if !isActive {
            isActive = true
            configure(ducked: false)
        }
        releaseLater(after: play(.finish))
    }

    /// Sample of a sound set in Settings. During a rest the session stays for its signals;
    /// otherwise it goes once the sample has played.
    func preview(_ set: SoundSet) {
        let temporary = !isActive || endTask != nil
        if !isActive {
            isActive = true
            configure(ducked: false)
        }
        let length = play(.restEnd, set: set)
        if temporary { releaseLater(after: length) }
    }

    /// The app is back in front: restart audio if an interruption ended without notice.
    func resumeIfNeeded() {
        guard isActive, !engine.isRunning || isDucked else { return }
        configure(ducked: false)
    }

    /// `endTask` is nil while a rest holds the session, set only while a release is pending.
    private func cancelRelease() {
        endTask?.cancel()
        endTask = nil
    }

    private func releaseLater(after seconds: TimeInterval) {
        endTask?.cancel()
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 1))
            while self?.speech.isSpeaking == true, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            self?.end()
        }
    }

    // MARK: - Playback

    /// Returns the sound's length in seconds, 0 when nothing played.
    @discardableResult
    private func play(_ cue: SoundCue, set: SoundSet? = nil) -> TimeInterval {
        guard isActive, let set = set ?? settings.soundSet else { return 0 }
        duck()
        guard engine.isRunning else { return 0 }
        let buffer = buffer(cue, set)
        let player = cue == .countdown ? tickPlayer : signalPlayer
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        let length = TimeInterval(buffer.frameLength) / SoundSynth.sampleRate
        scheduleUnduck(after: length)
        return length
    }

    private func speak(_ text: String, after delay: TimeInterval = 0) {
        guard isActive, settings.voicePrompts, !text.isEmpty else { return }
        duck()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.preUtteranceDelay = delay
        speech.stopSpeaking(at: .immediate)
        speech.speak(utterance)
        scheduleUnduck(after: delay + 0.5)
    }

    private func vibrate(strong: Bool) {
        guard settings.vibration else { return }
        // 1519 is the short "peek" tap; the standard vibration marks the end.
        AudioServicesPlaySystemSound(strong ? kSystemSoundID_Vibrate : 1519)
    }

    private func buffer(_ cue: SoundCue, _ set: SoundSet) -> AVAudioPCMBuffer {
        let key = "\(set.rawValue).\(cue)"
        if let buffer = buffers[key] { return buffer }
        let samples = SoundSynth.samples(cue, in: set)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        buffers[key] = buffer
        return buffer
    }

    /// The voice speaks the interface language; looked up once.
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        // The full code keeps the user's region ("en-GB"), when it is the same language.
        let current = AVSpeechSynthesisVoice.currentLanguageCode()
        if current.hasPrefix(language), let voice = AVSpeechSynthesisVoice(language: current) { return voice }
        return AVSpeechSynthesisVoice(language: language)
    }()

    // MARK: - Session

    /// Music is ducked for the signal, not for the whole rest.
    private func duck() {
        unduckTask?.cancel()
        // The ambient category never ducks: restarting would only cut the sound just scheduled.
        guard settings.ignoreSilentMode else {
            if !engine.isRunning { configure(ducked: false) }
            return
        }
        guard !isDucked else { return }
        configure(ducked: true)
    }

    /// The 3-2-1 and the end come close together, so the music returns only after a quiet second.
    private func scheduleUnduck(after delay: TimeInterval) {
        unduckTask?.cancel()
        unduckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay + 1))
            while self?.speech.isSpeaking == true, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled, let self, self.isActive, self.isDucked else { return }
            // Restarting the session in the background lets iOS suspend the app mid-rest,
            // so the music stays ducked until the app is back in front or the rest ends.
            guard UIApplication.shared.applicationState == .active else { return }
            self.configure(ducked: false)
        }
    }

    private func release() {
        unduckTask?.cancel()
        isDucked = false
        players.forEach { $0.stop() }
        engine.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ducking is applied on activation, so the session is restarted to switch it.
    private func configure(ducked: Bool) {
        // "Ignore Silent Mode" off follows the switch, but iOS then also silences the app on the lock screen.
        let ignoreSilent = settings.ignoreSilentMode
        if engine.isRunning {
            players.forEach { $0.stop() }
            engine.stop()
            try? session.setActive(false)
        }
        do {
            if ignoreSilent {
                try session.setCategory(.playback, options: ducked ? [.mixWithOthers, .duckOthers] : [.mixWithOthers])
            } else {
                try session.setCategory(.ambient)
            }
            try session.setActive(true)
            try engine.start()
            players.forEach { $0.play() }
            isDucked = ducked && ignoreSilent
        } catch {
            isDucked = false
        }
    }

    private func connectPlayers() {
        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
    }

    /// After a media services reset the old engine and nodes are unusable. The buffers are plain PCM and stay.
    private func rebuildEngine() {
        players.forEach { $0.stop() }
        engine.stop()
        engine = AVAudioEngine()
        tickPlayer = AVAudioPlayerNode()
        signalPlayer = AVAudioPlayerNode()
        connectPlayers()
        isDucked = false
        guard isActive else { return }
        configure(ducked: false)
    }

    private func observe() {
        let center = NotificationCenter.default
        // A call takes the audio; the rest runs on in real time (SPEC D20) and the audio comes back after it.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                guard let self, self.isActive, type == .ended else { return }
                self.configure(ducked: false)
            }
        })
        // Headphones and other route changes stop the engine. Any engine: this one may be rebuilt.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeIfNeeded() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildEngine() }
        })
    }
}
