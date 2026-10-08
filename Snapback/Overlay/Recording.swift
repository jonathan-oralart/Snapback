import AVFoundation
import CoreGraphics

struct EmptyRecording: Error {}

/// A screen recording to pick frames from: the time of every frame, and the image at any of them.
/// It never changes after opening, and frames are decoded off the main thread.
nonisolated final class Recording: @unchecked Sendable {
    let url: URL
    /// Every frame's presentation time, in order. Screen recordings only add a frame when something
    /// changes, so these are uneven, and stepping goes by index rather than by a fixed interval.
    let times: [CMTime]
    /// A temporary recording that hasn't been kept is removed once nothing uses it.
    private let deletesFile: Bool
    /// Exact frames, for showing and sending.
    private let exactGenerator: AVAssetImageGenerator
    /// The nearest quick-to-decode frame, while dragging along the timeline.
    private let roughGenerator: AVAssetImageGenerator
    /// Small frames for the timeline.
    private let thumbnailGenerator: AVAssetImageGenerator

    private init(url: URL, asset: AVURLAsset, times: [CMTime], deletesFile: Bool) {
        self.url = url
        self.times = times
        self.deletesFile = deletesFile
        exactGenerator = AVAssetImageGenerator(asset: asset)
        exactGenerator.requestedTimeToleranceBefore = .zero
        exactGenerator.requestedTimeToleranceAfter = .zero
        roughGenerator = AVAssetImageGenerator(asset: asset)
        thumbnailGenerator = AVAssetImageGenerator(asset: asset)
    }

    /// Reads every frame's time without decoding any of them.
    static func open(_ url: URL, deletesFile: Bool) async throws -> Recording {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw EmptyRecording() }
        let times = try await Task.detached(priority: .userInitiated) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            reader.startReading()
            var times: [CMTime] = []
            while let sample = output.copyNextSampleBuffer() {
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                if time.isValid && CMSampleBufferGetNumSamples(sample) > 0 { times.append(time) }
            }
            return times.sorted()
        }.value
        guard !times.isEmpty else { throw EmptyRecording() }
        return Recording(url: url, asset: asset, times: times, deletesFile: deletesFile)
    }

    deinit {
        if deletesFile { try? FileManager.default.removeItem(at: url) }
    }

    /// Seconds from the first frame.
    func seconds(_ time: CMTime) -> Double {
        (time - times[0]).seconds
    }

    var duration: Double { seconds(times[times.count - 1]) }

    /// The frame closest to a point in the recording, in seconds from the start.
    func index(near seconds: Double) -> Int {
        let target = times[0] + CMTime(seconds: seconds, preferredTimescale: times[0].timescale)
        let after = times.partitioningIndex { $0 >= target }
        if after == 0 { return 0 }
        if after == times.count { return times.count - 1 }
        return (target - times[after - 1]) <= (times[after] - target) ? after - 1 : after
    }

    /// The image at `time`, with the time of the frame it actually is.
    @concurrent func image(at time: CMTime, exact: Bool) async throws -> (image: CGImage, time: CMTime) {
        let result = try await (exact ? exactGenerator : roughGenerator).image(at: time)
        return (result.image, result.actualTime)
    }

    /// Small images spread evenly in time through the recording, for the timeline.
    @concurrent func thumbnails(count: Int, height: CGFloat) async -> [CGImage] {
        thumbnailGenerator.maximumSize = CGSize(width: 0, height: height)
        // By time, matching the timeline: the middle of each slot.
        let picks = (0..<count).map { times[index(near: duration * (Double($0) + 0.5) / Double(count))] }
        var images: [CGImage] = []
        for time in picks {
            if let image = try? await thumbnailGenerator.image(at: time).image { images.append(image) }
        }
        return images
    }
}

nonisolated private extension Array {
    /// The first index where `predicate` holds, for an array where it's false then true.
    func partitioningIndex(where predicate: (Element) -> Bool) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if predicate(self[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}
