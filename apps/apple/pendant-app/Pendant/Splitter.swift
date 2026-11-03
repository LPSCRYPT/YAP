import Foundation

/// Cuts one long recording into separate conversations, like Omi:
/// 2 minutes of quiet ends a conversation, and the quiet stretches are left out.
/// Runs on the phone, works on the 16-bit PCM WAV the rest of the app uses.
enum Splitter {
    /// A gap this long with no talking starts a new conversation.
    static let gapSeconds = 120
    /// Quiet kept before and after each conversation, so words aren't clipped.
    static let padSeconds = 2

    struct Piece {
        let offsetSeconds: Int   // where it starts in the original recording
        let wav: Data
    }

    /// Returns nil when nothing needs cutting (no quiet stretch of 2+ minutes),
    /// otherwise the conversations found (empty if it was all quiet).
    static func split(_ wav: Data) -> [Piece]? {
        guard let pcm = PCM(wav), pcm.rate > 0 else { return nil }
        let voiced = voicedSeconds(pcm)
        let total = voiced.count
        guard total > gapSeconds else { return nil }

        // Group talking seconds; a quiet run of gapSeconds or more separates groups
        var groups: [(first: Int, last: Int)] = []
        var lastVoiced: Int?
        for s in 0..<total where voiced[s] {
            if let lv = lastVoiced, s - lv - 1 < gapSeconds, !groups.isEmpty {
                groups[groups.count - 1].last = s
            } else {
                groups.append((s, s))
            }
            lastVoiced = s
        }

        // Nothing to do if there's no long quiet stretch anywhere (start, middle or end)
        let leading = groups.first?.first ?? total
        let trailing = total - 1 - (groups.last?.last ?? -1)
        if groups.count == 1, leading < gapSeconds, trailing < gapSeconds { return nil }

        return groups.map { g in
            let start = max(0, g.first - padSeconds)
            let end = min(total, g.last + 1 + padSeconds)
            return Piece(offsetSeconds: start, wav: pcm.wav(fromSecond: start, toSecond: end))
        }
    }

    /// One flag per second: did someone (probably) talk in it?
    /// Loudness is measured in 30 ms frames and compared with the room's background level,
    /// so it adapts to quiet rooms and noisy streets.
    private static func voicedSeconds(_ pcm: PCM) -> [Bool] {
        let frame = max(1, pcm.rate * 3 / 100)
        let frameCount = pcm.sampleCount / frame
        guard frameCount > 0 else { return [] }

        var level = [Double](repeating: 0, count: frameCount)
        pcm.samples.withUnsafeBufferPointer { s in
            for f in 0..<frameCount {
                var sum = 0.0
                for i in (f * frame)..<((f + 1) * frame) { let v = Double(s[i]); sum += v * v }
                level[f] = (sum / Double(frame)).squareRoot()
            }
        }

        // Background = the quietest 10% of the recording. Talking is clearly (2x, ~6 dB) louder.
        let floor = level.sorted()[frameCount / 10]
        let threshold = max(floor * 2, 120)

        let seconds = Int((Double(pcm.sampleCount) / Double(pcm.rate)).rounded(.up))
        var loudFrames = [Int](repeating: 0, count: seconds)
        for f in 0..<frameCount where level[f] > threshold {
            let s = min(seconds - 1, f * frame / pcm.rate)
            loudFrames[s] += 1
        }
        // A second counts as talking if at least ~10% of it (3 frames) is loud,
        // which ignores single clicks and bumps.
        return loudFrames.map { $0 >= 3 }
    }

    /// The samples of a mono 16-bit PCM WAV file.
    private struct PCM {
        let rate: Int
        let samples: [Int16]
        var sampleCount: Int { samples.count }

        init?(_ data: Data) {
            let b = [UInt8](data)
            func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
            func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
            guard b.count >= 12, b[0...3] == [0x52, 0x49, 0x46, 0x46] /* RIFF */ else { return nil }

            var rate = 0, channels = 0, bits = 0
            var i = 12
            while i + 8 <= b.count {
                let id = String(decoding: b[i..<(i + 4)], as: UTF8.self)
                let size = u32(i + 4)
                let body = i + 8
                if id == "fmt ", body + 16 <= b.count {
                    channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
                } else if id == "data" {
                    guard channels == 1, bits == 16 else { return nil }
                    let end = min(b.count, body + size) & ~1
                    var s = [Int16](repeating: 0, count: (end - body) / 2)
                    let n = s.count
                    s.withUnsafeMutableBytes { $0.copyBytes(from: b[body..<(body + 2 * n)]) }
                    self.rate = rate
                    self.samples = s
                    return
                }
                i = body + size + (size & 1)
            }
            return nil
        }

        func wav(fromSecond a: Int, toSecond z: Int) -> Data {
            let lo = min(samples.count, a * rate)
            let hi = min(samples.count, z * rate)
            let slice = samples[lo..<hi]
            let bytes = slice.withUnsafeBufferPointer { Data(buffer: $0) }
            return PendantOpus.wavHeader(dataBytes: bytes.count, rate: rate) + bytes
        }
    }
}
