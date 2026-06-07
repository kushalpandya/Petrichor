import AVFoundation
import Foundation
import SFBAudioEngine

// MARK: - Delegate Protocol

/// Delegate protocol for receiving SpatialAudioRenderer playback events
protocol SpatialAudioRendererDelegate: AnyObject {
    /// Called on the main queue when the renderer finishes playing the current decoder
    func spatialAudioRendererDidReachEnd(_ renderer: SpatialAudioRenderer)
    /// Called when the renderer encounters an unrecoverable error
    func spatialAudioRenderer(_ renderer: SpatialAudioRenderer, encounteredError error: Error)
}

// MARK: - SpatialAudioRenderer

/// Output engine that renders decoded PCM through `AVSampleBufferAudioRenderer`.
///
/// Unlike `AVAudioEngine`, audio rendered through `AVSampleBufferAudioRenderer` is
/// eligible for macOS system-level Spatial Audio: when AirPods (3rd gen)/Pro/Max are
/// connected, the Sound menu offers "Spatialize Stereo" (Fixed / Head Tracked) and the
/// OS performs the spatialization and head tracking natively, exactly like Apple Music.
final class SpatialAudioRenderer {
    weak var delegate: SpatialAudioRendererDelegate?

    /// In-app effects (stereo widening, EQ, preamp) applied to PCM before enqueueing
    let effects = AudioEffectsChain()

    // MARK: - Private Properties

    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let decodeQueue = DispatchQueue(label: "org.Petrichor.SpatialAudioRenderer", qos: .userInitiated)

    private var decoder: PCMDecoding?
    private var framesDecoded: AVAudioFramePosition = 0
    private var decodingComplete = false
    private var endObserver: Any?
    private var rendererStatusObservation: NSKeyValueObservation?

    /// Converter used to interleave PCM before enqueueing (cached per input format)
    private var interleaveConverter: AVAudioConverter?

    /// Incremented on every play/stop so stale media-request callbacks are ignored
    private var generation = 0

    /// Number of frames decoded per enqueued sample buffer
    private static let framesPerChunk: AVAudioFrameCount = 4096

    // MARK: - Public Properties

    var volume: Float {
        get { renderer.volume }
        set { renderer.volume = newValue }
    }

    /// Current playback position in seconds
    var currentTime: Double {
        let seconds = synchronizer.currentTime().seconds
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return duration > 0 ? min(seconds, duration) : seconds
    }

    /// Duration of the current track in seconds
    var duration: Double {
        decodeQueue.sync {
            guard let decoder, decoder.length > 0, decoder.processingFormat.sampleRate > 0 else { return 0 }
            return Double(decoder.length) / decoder.processingFormat.sampleRate
        }
    }

    var isPlaying: Bool {
        synchronizer.rate > 0
    }

    // MARK: - Initialization

    init() {
        synchronizer.addRenderer(renderer)

        // Allow the OS to spatialize any decodable layout; this is what makes
        // "Spatialize Stereo" appear in the Sound menu instead of "Not Available"
        renderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel

        rendererStatusObservation = renderer.observe(\.status) { [weak self] renderer, _ in
            guard let self = self, renderer.status == .failed else { return }
            let error = renderer.error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.unknown.rawValue)
            Logger.error("Spatial audio renderer failed: \(error.localizedDescription)")
            self.delegate?.spatialAudioRenderer(self, encounteredError: error)
        }
    }

    deinit {
        rendererStatusObservation?.invalidate()
        removeEndObserver()
    }

    // MARK: - Playback Control

    /// Starts playing the given decoder from its current position
    func play(decoder: PCMDecoding, startPaused: Bool = false) throws {
        if !decoder.isOpen {
            try decoder.open()
        }

        let startTime: CMTime = try decodeQueue.sync {
            generation += 1
            renderer.stopRequestingMediaData()
            renderer.flush()
            removeEndObserver()

            guard decoder.processingFormat.sampleRate > 0 else {
                throw AudioPlayerError.invalidFormat
            }

            self.decoder = decoder
            framesDecoded = max(decoder.position, 0)
            decodingComplete = false
            effects.configure(format: decoder.processingFormat)
            return CMTime(value: framesDecoded, timescale: CMTimeScale(decoder.processingFormat.sampleRate))
        }

        synchronizer.setRate(startPaused ? 0 : 1, time: startTime)
        decodeQueue.sync { startRequestingMedia() }
    }

    func pause() {
        synchronizer.rate = 0
    }

    func resume() {
        synchronizer.rate = 1
    }

    func stop() {
        decodeQueue.sync {
            generation += 1
            renderer.stopRequestingMediaData()
            renderer.flush()
            removeEndObserver()
            decoder = nil
            framesDecoded = 0
            decodingComplete = false
        }
        synchronizer.rate = 0
    }

    /// Seeks to the given time in seconds
    /// - Returns: true if the seek succeeded
    @discardableResult
    func seek(to time: Double) -> Bool {
        decodeQueue.sync {
            guard let decoder, decoder.supportsSeeking else { return false }

            let sampleRate = decoder.processingFormat.sampleRate
            var targetFrame = AVAudioFramePosition(time * sampleRate)
            if decoder.length > 0 {
                targetFrame = min(max(targetFrame, 0), decoder.length)
            }

            do {
                renderer.stopRequestingMediaData()
                renderer.flush()
                removeEndObserver()
                try decoder.seek(to: targetFrame)
            } catch {
                Logger.error("Spatial audio renderer seek failed: \(error.localizedDescription)")
                startRequestingMedia()
                return false
            }

            framesDecoded = targetFrame
            decodingComplete = false

            let rate = synchronizer.rate
            synchronizer.setRate(rate, time: CMTime(value: targetFrame, timescale: timescale))
            startRequestingMedia()
            return true
        }
    }

    // MARK: - Private Methods

    private var timescale: CMTimeScale {
        CMTimeScale(decoder?.processingFormat.sampleRate ?? 44100)
    }

    private func startRequestingMedia() {
        let requestGeneration = generation
        renderer.requestMediaDataWhenReady(on: decodeQueue) { [weak self] in
            guard let self = self, self.generation == requestGeneration else { return }
            self.provideMedia()
        }
    }

    /// Decodes and enqueues audio while the renderer wants more data; runs on decodeQueue
    private func provideMedia() {
        guard let decoder, !decodingComplete else { return }

        let format = decoder.processingFormat

        while renderer.isReadyForMoreMediaData {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.framesPerChunk) else {
                finishDecoding()
                return
            }

            do {
                try decoder.decode(into: buffer, length: Self.framesPerChunk)
            } catch {
                Logger.error("Spatial audio renderer decode failed: \(error.localizedDescription)")
                finishDecoding()
                delegate?.spatialAudioRenderer(self, encounteredError: error)
                return
            }

            guard buffer.frameLength > 0 else {
                finishDecoding()
                return
            }

            let processed = effects.process(buffer)

            guard let interleaved = interleavedIfNeeded(processed) else {
                Logger.error("Failed to interleave audio for the sample buffer renderer")
                finishDecoding()
                return
            }

            let presentationTime = CMTime(value: framesDecoded, timescale: CMTimeScale(format.sampleRate))
            guard let sampleBuffer = makeSampleBuffer(from: interleaved, presentationTime: presentationTime) else {
                Logger.error("Failed to create sample buffer for spatial audio renderer")
                finishDecoding()
                return
            }

            renderer.enqueue(sampleBuffer)
            framesDecoded += AVAudioFramePosition(buffer.frameLength)
        }
    }

    /// Stops media requests and arranges end-of-track notification; runs on decodeQueue
    private func finishDecoding() {
        decodingComplete = true
        renderer.stopRequestingMediaData()

        let endTime = NSValue(time: CMTime(value: framesDecoded, timescale: timescale))
        endObserver = synchronizer.addBoundaryTimeObserver(forTimes: [endTime], queue: .main) { [weak self] in
            guard let self = self else { return }
            self.removeEndObserver()
            self.delegate?.spatialAudioRendererDidReachEnd(self)
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            synchronizer.removeTimeObserver(endObserver)
            self.endObserver = nil
        }
    }

    /// Returns an interleaved copy of the buffer when needed; runs on decodeQueue.
    ///
    /// `AVSampleBufferAudioRenderer` renders through an AudioQueue, which only
    /// accepts interleaved linear PCM — non-interleaved buffers (e.g. FLAC decoder
    /// output or the effects chain's standard format) enqueue without error but
    /// render as silence ("SSP::Render: CopySlice" failures in the system log).
    private func interleavedIfNeeded(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard !buffer.format.isInterleaved else { return buffer }

        if interleaveConverter?.inputFormat != buffer.format {
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: buffer.format.sampleRate,
                channels: buffer.format.channelCount,
                interleaved: true
            ), let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
                return nil
            }
            interleaveConverter = converter
        }

        // A fresh output buffer per chunk so enqueued sample buffers never share memory
        guard let converter = interleaveConverter,
              let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: buffer.frameLength) else {
            return nil
        }

        do {
            try converter.convert(to: output, from: buffer)
        } catch {
            Logger.error("Interleave conversion failed: \(error.localizedDescription)")
            return nil
        }

        guard output.frameLength == buffer.frameLength else { return nil }
        return output
    }

    /// Wraps decoded PCM in a CMSampleBuffer for the renderer
    private func makeSampleBuffer(from buffer: AVAudioPCMBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: buffer.format.formatDescription,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard createStatus == noErr, let sampleBuffer else { return nil }

        let fillStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            bufferList: buffer.audioBufferList
        )

        guard fillStatus == noErr else { return nil }
        return sampleBuffer
    }
}
