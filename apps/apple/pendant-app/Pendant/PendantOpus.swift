import AVFoundation
import Foundation

/// Turns the pendant's compressed .opus note back into a normal WAV, right on the phone.
///
/// File format (written by the pendant firmware, main/audio.c), little endian:
///   "PDO1"  u16 sample_rate  u16 frame_samples      then per 20 ms frame:  u16 len  <len bytes of Opus>
enum PendantOpus {
    enum Failure: Error { case badFile, noDecoder, decodeFailed }

    static func wav(from data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count >= 8, b[0] == 0x50, b[1] == 0x44, b[2] == 0x4F, b[3] == 0x31 else { throw Failure.badFile }
        let rate = Double(Int(b[4]) | Int(b[5]) << 8)
        let frameSamples = Int(b[6]) | Int(b[7]) << 8
        guard rate > 0, frameSamples > 0 else { throw Failure.badFile }

        var packets: [Range<Int>] = []
        var i = 8
        while i + 2 <= b.count {
            let n = Int(b[i]) | Int(b[i + 1]) << 8
            i += 2
            guard n > 0, i + n <= b.count else { break }
            packets.append(i ..< i + n)
            i += n
        }
        guard !packets.isEmpty else { throw Failure.badFile }

        // Apple's Opus decoder works at 48 kHz. Opus can be decoded at any rate, so decode at
        // 48 kHz and then convert down to the pendant's 16 kHz.
        let decodeRate = 48000.0
        let framesPerPacket = AVAudioFrameCount(Double(frameSamples) * decodeRate / rate)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: decodeRate, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(framesPerPacket), mBytesPerFrame: 0, mChannelsPerFrame: 1,
            mBitsPerChannel: 0, mReserved: 0)
        guard let opusFormat = AVAudioFormat(streamDescription: &asbd),
              let pcm48 = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: decodeRate, channels: 1, interleaved: false),
              let pcmOut = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true),
              let decoder = AVAudioConverter(from: opusFormat, to: pcm48),
              let resampler = AVAudioConverter(from: pcm48, to: pcmOut)
        else { throw Failure.noDecoder }

        // 1) Opus packets -> one long 48 kHz buffer
        let maxPacket = packets.map(\.count).max() ?? 1
        let packet = AVAudioCompressedBuffer(format: opusFormat, packetCapacity: 1, maximumPacketSize: maxPacket)
        guard let frame = AVAudioPCMBuffer(pcmFormat: pcm48, frameCapacity: framesPerPacket * 2),
              let all = AVAudioPCMBuffer(pcmFormat: pcm48, frameCapacity: framesPerPacket * AVAudioFrameCount(packets.count + 2))
        else { throw Failure.noDecoder }

        for r in packets {
            b.withUnsafeBytes { src in
                packet.data.copyMemory(from: src.baseAddress! + r.lowerBound, byteCount: r.count)
            }
            packet.byteLength = UInt32(r.count)
            packet.packetCount = 1
            packet.packetDescriptions?[0] = AudioStreamPacketDescription(
                mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(r.count))

            frame.frameLength = 0
            var fed = false
            var error: NSError?
            let status = decoder.convert(to: frame, error: &error) { _, inputStatus in
                if fed { inputStatus.pointee = .noDataNow; return nil }
                fed = true
                inputStatus.pointee = .haveData
                return packet
            }
            if status == .error { throw error ?? Failure.decodeFailed }
            let n = Int(frame.frameLength)
            let room = Int(all.frameCapacity - all.frameLength)
            guard n > 0, room > 0 else { continue }
            let copy = min(n, room)
            (all.floatChannelData![0] + Int(all.frameLength)).update(from: frame.floatChannelData![0], count: copy)
            all.frameLength += AVAudioFrameCount(copy)
        }
        guard all.frameLength > 0 else { throw Failure.decodeFailed }

        // 2) 48 kHz float -> 16 kHz 16-bit
        let outFrames = AVAudioFrameCount(Double(all.frameLength) * rate / decodeRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: pcmOut, frameCapacity: outFrames) else { throw Failure.noDecoder }
        var given = false
        var error: NSError?
        let status = resampler.convert(to: out, error: &error) { _, inputStatus in
            if given { inputStatus.pointee = .endOfStream; return nil }
            given = true
            inputStatus.pointee = .haveData
            return all
        }
        if status == .error { throw error ?? Failure.decodeFailed }

        let samples = Data(bytes: out.int16ChannelData![0], count: Int(out.frameLength) * 2)
        return wavHeader(dataBytes: samples.count, rate: Int(rate)) + samples
    }

    static func wavHeader(dataBytes: Int, rate: Int) -> Data {
        var h = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; h.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; h.append(Data(bytes: &x, count: 2)) }
        h.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        h.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16)
        u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        h.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        return h
    }
}
