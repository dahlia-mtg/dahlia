import CoreGraphics
import DahliaRuntimeSupport
import Foundation
import os

/// A single decode lane. Cacheable background work and interactive display work use
/// different instances so a thumbnail backlog cannot delay a user-initiated decode.
actor ScreenshotImageDecodeWorker {
    enum Lane: String, Sendable {
        case cacheable
        case interactive
    }

    private static let logger = Logger(subsystem: "com.dahlia", category: "ScreenshotImageLoading")
    private let lane: Lane

    init(lane: Lane) {
        self.lane = lane
    }

    func decode(
        _ data: Data,
        maxPixelSize: Int,
        requestedAt: ContinuousClock.Instant
    ) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let decodeStartedAt = ContinuousClock.now
        let queueWait = requestedAt.duration(to: decodeStartedAt)
        let image = CGImageDecoder.decode(data, maxPixelSize: maxPixelSize)
        let decodeDuration = decodeStartedAt.duration(to: .now)
        Self.logger.debug(
            """
            Screenshot decode lane=\(self.lane.rawValue, privacy: .public) \
            queueWaitMs=\(Self.milliseconds(queueWait), privacy: .public) \
            decodeMs=\(Self.milliseconds(decodeDuration), privacy: .public) \
            maxPixelSize=\(maxPixelSize, privacy: .public)
            """
        )
        return Task.isCancelled ? nil : image
    }

    nonisolated static func recordOverlayPresented(
        requestedAt: ContinuousClock.Instant,
        hasPreview: Bool
    ) {
        logger.debug(
            """
            Screenshot overlay presented latencyMs=\(milliseconds(requestedAt.duration(to: .now)), privacy: .public) \
            hasPreview=\(hasPreview, privacy: .public)
            """
        )
    }

    nonisolated static func recordInteractiveImageApplied(requestedAt: ContinuousClock.Instant) {
        logger.debug(
            "Screenshot interactive image applied latencyMs=\(milliseconds(requestedAt.duration(to: .now)), privacy: .public)"
        )
    }

    private nonisolated static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
