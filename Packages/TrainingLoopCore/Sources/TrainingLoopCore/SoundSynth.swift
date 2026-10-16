import Foundation

/// What a signal announces (TECH T7): the 3-2-1 tick, the end of a rest and the end of the workout.
public enum SoundCue: CaseIterable, Sendable {
    case countdown, restEnd, finish
}

/// Synthesizes the signals in code in the style of iOS system sounds: soft attack, natural decay,
/// mid register and a little room. A copy of SetLoop's (TECH T7). No audio files, no licenses.
public enum SoundSynth {
    public static let sampleRate = 44_100.0
    /// Peak level of every sound, leaving headroom for the mixer.
    public static let peak: Float = 0.8
    /// Everything three semitones below the lab page's default, picked by ear.
    static let transpose = pow(2, -3.0 / 12)

    /// Mono samples at `sampleRate`, normalized to `peak`.
    public static func samples(_ cue: SoundCue, in set: SoundSet) -> [Float] {
        let (voice, notes) = set.score(cue)
        return render(voice, notes.map { ($0.frequency * transpose, $0.start) })
    }

    static func render(_ voice: Voice, _ notes: [(frequency: Double, start: TimeInterval)]) -> [Float] {
        let length = (notes.map(\.start).max() ?? 0) + voice.length
        var dry = [Float](repeating: 0, count: Int((length * sampleRate).rounded(.up)))
        for note in notes {
            let first = Int((note.start * sampleRate).rounded())
            for i in 0..<max(dry.count - first, 0) {
                dry[first + i] += Float(voice.sample(note.frequency, Double(i) / sampleRate))
            }
        }
        var output = reverb(dry)
        // A cut tail never clicks.
        let fade = Int(0.15 * sampleRate)
        for i in 0..<min(fade, output.count) {
            output[output.count - 1 - i] *= Float(i) / Float(fade)
        }
        let maxLevel = output.map(abs).max() ?? 0
        guard maxLevel > 0 else { return output }
        let gain = peak / maxLevel
        return output.map { $0 * gain }
    }

    /// Small Schroeder reverb: 4 combs and 2 allpasses, 18 % wet, 0.4 s tail.
    static func reverb(_ x: [Float]) -> [Float] {
        let n = x.count + Int(0.4 * sampleRate)
        var wet = [Float](repeating: 0, count: n)
        for delay in [1116, 1188, 1277, 1356] {
            var buffer = [Float](repeating: 0, count: delay)
            var index = 0
            for k in 0..<n {
                let out = buffer[index]
                buffer[index] = (k < x.count ? x[k] : 0) + out * 0.72
                index = (index + 1) % delay
                wet[k] += out / 4
            }
        }
        for delay in [556, 441] {
            var buffer = [Float](repeating: 0, count: delay)
            var index = 0
            for k in 0..<n {
                let stored = buffer[index], input = wet[k]
                buffer[index] = input + stored * 0.5
                index = (index + 1) % delay
                wet[k] = stored - input
            }
        }
        return (0..<n).map { k in (k < x.count ? x[k] : 0) + 0.18 * wet[k] }
    }

    /// A sum of decaying partials, with an optional pitch drop at the start (woodblock).
    struct Voice {
        /// Frequency ratio, amplitude, decay time constant in seconds.
        var partials: [(ratio: Double, amplitude: Double, decay: Double)]
        var attack: Double
        var drop: Double = 0

        /// Until about -40 dB, at most 2.5 s; the reverb adds its own tail.
        var length: TimeInterval { min(2.5, (partials.map(\.decay).max() ?? 0) * 4.6) }

        func sample(_ frequency: Double, _ t: TimeInterval) -> Double {
            let pitch = drop > 0 ? frequency * (1 + drop * exp(-t / 0.005)) : frequency
            let sum = partials.reduce(0) { sum, p in
                sum + p.amplitude * exp(-t / p.decay) * sin(2 * .pi * pitch * p.ratio * t)
            }
            return min(1, t / attack) * sum
        }

        // Tails are 0.3 of the lab page's, shortened by ear.
        static let glass = Voice(partials: [(1, 1, 0.9), (2.76, 0.3, 0.25), (5.4, 0.12, 0.1), (8.9, 0.05, 0.05)], attack: 0.003).shortened(0.3)
        static let marimba = Voice(partials: [(1, 1, 0.4), (3.93, 0.3, 0.06), (9.2, 0.06, 0.02)], attack: 0.002).shortened(0.3)
        static let note = Voice(partials: [(1, 1, 0.45), (2, 0.35, 0.2), (3, 0.1, 0.1)], attack: 0.006).shortened(0.3)
        static let tink = Voice(partials: [(1, 1, 0.12), (2.76, 0.3, 0.04)], attack: 0.001)
        static let wood = Voice(partials: [(1, 1, 0.035), (2.6, 0.4, 0.015)], attack: 0.001, drop: 0.3)
        static let tock = Voice(partials: [(1, 1, 0.05), (2, 0.15, 0.02)], attack: 0.001)

        /// Same timbre with a shorter tail.
        func shortened(_ factor: Double) -> Voice {
            var voice = self
            voice.partials = partials.map { ($0.ratio, $0.amplitude, $0.decay * factor) }
            return voice
        }
    }

    enum Pitch {
        static let a4 = 440.0, c5 = 523.25, cSharp5 = 554.37, e5 = 659.25, g5 = 783.99, a5 = 880.0, c6 = 1046.5
    }
}

extension SoundSet {
    /// The end of a rest goes up, like SetLoop's work signal; the finish is a rising run.
    func score(_ cue: SoundCue) -> (SoundSynth.Voice, [(frequency: Double, start: TimeInterval)]) {
        typealias P = SoundSynth.Pitch
        switch (self, cue) {
        case (.glass, .countdown): return (.tink, [(1319, 0)])
        case (.glass, .restEnd): return (.glass, [(P.e5, 0), (P.a5, 0.11)])
        case (.glass, .finish): return (.glass, [(P.c5, 0), (P.e5, 0.12), (P.g5, 0.24), (P.c6, 0.36)])

        case (.marimba, .countdown): return (.wood, [(1100, 0)])
        case (.marimba, .restEnd): return (.marimba, [(P.c5, 0), (P.g5, 0.1)])
        case (.marimba, .finish): return (.marimba, [(P.c5, 0), (P.e5, 0.1), (P.g5, 0.2), (P.c6, 0.3)])

        case (.note, .countdown): return (.tock, [(800, 0)])
        case (.note, .restEnd): return (.note, [(P.a4, 0), (P.e5, 0.14)])
        case (.note, .finish): return (.note, [(P.a4, 0), (P.cSharp5, 0.12), (P.e5, 0.24), (P.a5, 0.36)])
        }
    }
}
