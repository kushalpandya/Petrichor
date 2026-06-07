import AVFoundation
import Foundation

/// Applies the in-app audio effects (stereo widening, equalizer, preamp) to decoded
/// PCM using an `AVAudioEngine` in offline manual rendering mode.
///
/// The playback output runs through `AVSampleBufferAudioRenderer` (see
/// `SpatialAudioRenderer`), which has no insert-effect graph of its own, so effects
/// are rendered into the PCM before it is enqueued. Decoder formats that are not
/// Float32 deinterleaved (e.g. Int16 interleaved from WAV/AIFF) are converted on the
/// way in. When no effect is enabled the input buffers pass through untouched
/// (bit-exact, no conversion).
final class AudioEffectsChain {

    // MARK: - Private Properties

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var delayNode: AVAudioUnitDelay?
    private var eqNode: AVAudioUnitEQ?

    /// The decoder's format accepted by `process(_:)`
    private var sourceFormat: AVAudioFormat?
    /// Standard Float32 deinterleaved format the graph renders in
    private var chainFormat: AVAudioFormat?
    private var inputConverter: AVAudioConverter?
    private var convertedBuffer: AVAudioPCMBuffer?
    private var outputBuffer: AVAudioPCMBuffer?

    /// Input handoff to the source node render block (always in `chainFormat`)
    private var pendingBuffer: AVAudioPCMBuffer?
    private var pendingOffset: Int = 0

    private static let maximumFrames: AVAudioFrameCount = 8192
    private let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    // MARK: - Effect State

    /// Effect settings survive engine rebuilds on format changes
    private(set) var stereoWideningEnabled = false
    private(set) var eqEnabled = false
    private(set) var eqGains = [Float](repeating: 0, count: 10)
    private(set) var preampGain: Float = 0

    /// True when at least one effect needs rendering
    var isActive: Bool {
        stereoWideningEnabled || eqEnabled
    }

    // MARK: - Effect Control

    func setStereoWidening(enabled: Bool) {
        stereoWideningEnabled = enabled
        delayNode?.bypass = !enabled
    }

    func setEQEnabled(_ enabled: Bool) {
        eqEnabled = enabled
        eqNode?.bypass = !enabled
    }

    func setEQGains(_ gains: [Float]) {
        guard gains.count == eqGains.count else { return }
        eqGains = gains
        if let eqNode {
            for (index, gain) in gains.enumerated() {
                eqNode.bands[index].gain = gain
            }
        }
    }

    func setPreamp(_ gain: Float) {
        preampGain = gain
        eqNode?.globalGain = gain
    }

    // MARK: - Rendering

    /// Rebuilds the chain when the decoder format changes; called from the decode queue
    func configure(format: AVAudioFormat) {
        guard sourceFormat != format else { return }

        teardown()

        guard let chainFormat = AVAudioFormat(
            standardFormatWithSampleRate: format.sampleRate,
            channels: format.channelCount
        ) else {
            Logger.error("Effects chain unavailable for format: \(format)")
            return
        }

        if format == chainFormat {
            inputConverter = nil
            convertedBuffer = nil
        } else {
            guard let converter = AVAudioConverter(from: format, to: chainFormat),
                  let buffer = AVAudioPCMBuffer(pcmFormat: chainFormat, frameCapacity: Self.maximumFrames) else {
                Logger.error("Effects chain cannot convert from format: \(format)")
                return
            }
            inputConverter = converter
            convertedBuffer = buffer
        }

        let source = AVAudioSourceNode(format: chainFormat) { [weak self] _, _, frameCount, audioBufferList in
            self?.renderPendingInput(frameCount: frameCount, into: audioBufferList) ?? noErr
        }

        // Haas effect stereo widening, matching the previous AVAudioEngine graph
        let delay = AVAudioUnitDelay()
        delay.delayTime = 0.020
        delay.wetDryMix = 50
        delay.feedback = -10
        delay.lowPassCutoff = 15000
        delay.bypass = !stereoWideningEnabled

        let eq = AVAudioUnitEQ(numberOfBands: 10)
        for (index, frequency) in eqFrequencies.enumerated() {
            let band = eq.bands[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1.0
            band.gain = eqGains[index]
            band.bypass = false
        }
        eq.globalGain = preampGain
        eq.bypass = !eqEnabled

        do {
            // Manual rendering mode must be enabled before connecting nodes so the
            // graph is detached from the hardware output device
            try engine.enableManualRenderingMode(.offline, format: chainFormat, maximumFrameCount: Self.maximumFrames)

            engine.attach(source)
            engine.attach(delay)
            engine.attach(eq)
            engine.connect(source, to: delay, format: chainFormat)
            engine.connect(delay, to: eq, format: chainFormat)
            engine.connect(eq, to: engine.mainMixerNode, format: chainFormat)

            try engine.start()
        } catch {
            Logger.error("Failed to start audio effects chain: \(error.localizedDescription)")
            engine.stop()
            engine.detach(source)
            engine.detach(delay)
            engine.detach(eq)
            inputConverter = nil
            convertedBuffer = nil
            return
        }

        sourceNode = source
        delayNode = delay
        eqNode = eq
        outputBuffer = AVAudioPCMBuffer(pcmFormat: chainFormat, frameCapacity: Self.maximumFrames)
        sourceFormat = format
        self.chainFormat = chainFormat
        Logger.info("Audio effects chain configured: \(format.sampleRate)Hz, \(format.channelCount)ch")
    }

    /// Runs a decoded buffer through the effect chain; returns the input unchanged
    /// when no effect is enabled or the chain is unavailable. Called from the decode queue.
    func process(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard isActive else { return buffer }
        guard let sourceFormat, sourceFormat == buffer.format,
              let outputBuffer, engine.isRunning,
              buffer.frameLength <= Self.maximumFrames else {
            return buffer
        }

        let chainInput: AVAudioPCMBuffer
        if let inputConverter, let convertedBuffer {
            convertedBuffer.frameLength = 0
            do {
                try inputConverter.convert(to: convertedBuffer, from: buffer)
            } catch {
                Logger.error("Effects chain input conversion failed: \(error.localizedDescription)")
                return buffer
            }
            guard convertedBuffer.frameLength == buffer.frameLength else { return buffer }
            chainInput = convertedBuffer
        } else {
            chainInput = buffer
        }

        pendingBuffer = chainInput
        pendingOffset = 0
        outputBuffer.frameLength = 0

        do {
            let status = try engine.renderOffline(buffer.frameLength, to: outputBuffer)
            guard status == .success, outputBuffer.frameLength == buffer.frameLength else {
                Logger.warning("Effects chain render incomplete (\(String(describing: status))), bypassing")
                return buffer
            }
            return outputBuffer
        } catch {
            Logger.error("Effects chain render failed: \(error.localizedDescription)")
            return buffer
        }
    }

    // MARK: - Private Methods

    private func teardown() {
        engine.stop()
        if let sourceNode { engine.detach(sourceNode) }
        if let delayNode { engine.detach(delayNode) }
        if let eqNode { engine.detach(eqNode) }
        sourceNode = nil
        delayNode = nil
        eqNode = nil
        inputConverter = nil
        convertedBuffer = nil
        outputBuffer = nil
        pendingBuffer = nil
        sourceFormat = nil
        chainFormat = nil
    }

    /// Source node render block: supplies the pending input buffer to the engine
    private func renderPendingInput(
        frameCount: AVAudioFrameCount,
        into audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let outputBuffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

        guard let pendingBuffer, let channelData = pendingBuffer.floatChannelData else {
            for outputBuffer in outputBuffers where outputBuffer.mData != nil {
                memset(outputBuffer.mData, 0, Int(outputBuffer.mDataByteSize))
            }
            return noErr
        }

        let available = Int(pendingBuffer.frameLength) - pendingOffset
        let framesToCopy = max(0, min(Int(frameCount), available))

        for (channel, outputBuffer) in outputBuffers.enumerated() {
            guard let destination = outputBuffer.mData else { continue }
            let source = channelData[min(channel, Int(pendingBuffer.format.channelCount) - 1)]

            if framesToCopy > 0 {
                memcpy(destination, source + pendingOffset, framesToCopy * MemoryLayout<Float>.size)
            }
            if framesToCopy < Int(frameCount) {
                let remainder = destination + framesToCopy * MemoryLayout<Float>.size
                memset(remainder, 0, (Int(frameCount) - framesToCopy) * MemoryLayout<Float>.size)
            }
        }

        pendingOffset += framesToCopy
        return noErr
    }
}
