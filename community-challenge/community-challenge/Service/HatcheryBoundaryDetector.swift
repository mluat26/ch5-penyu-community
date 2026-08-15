import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import OSLog
import Vision

nonisolated struct HatcheryBoundaryDetection: Equatable {
    let boundary: HatcheryBoundary
    let orientedImageSize: CGSize
    let confidence: Float
}

/// Finds and stabilizes a visible quadrilateral in camera frames.
///
/// Vision work is synchronous so callers can choose the queue on which it
/// runs. Live tracking state is locked because camera teardown can reset the
/// detector while an analysis is finishing.
nonisolated final class HatcheryBoundaryDetector: @unchecked Sendable {
    private static let smoothingAlpha = 0.30
    private static let maximumJump = 0.18
    private static let retainedMissCount = 4
    private static let minimumArea = 0.08
    private static let maximumArea = 0.92
    private static let objectAnalysisInterval: TimeInterval = 0.20
    private static let objectAnalysisTimingTolerance: TimeInterval = 0.000_001

    struct Candidate {
        let boundary: HatcheryBoundary
        let confidence: Float
        let score: Double
    }

    private struct PendingDetection {
        var boundary: HatcheryBoundary
        var confidence: Float
        var confirmations: Int
    }

    private struct LiveState {
        var stable: HatcheryBoundaryDetection?
        var pending: PendingDetection?
        var missedAnalyses = 0
        var generation = 0
        var orientation: CGImagePropertyOrientation?
        var orientedImageSize: CGSize?
        var latestObjectDetection: HatcheryObjectDetection?
        var lastObjectAnalysisAt: TimeInterval?
    }

    private struct Analysis {
        let candidates: [Candidate]
        let observationCount: Int
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "community-challenge",
        category: "HatcheryBoundaryDetector"
    )
    /// An explicitly injected provider is primarily used by tests and keeps
    /// callers able to opt out of Core ML completely with an explicit `nil`.
    private let injectedObjectCandidateProvider: (any HatcheryObjectCandidateProviding)?
    private let loadsBundledObjectCandidateProvider: Bool
    private let stateLock = NSLock()
    private var liveState = LiveState()
    // Accessed under `stateLock`. Loading the compiled model happens only from
    // an analysis call, never while the SwiftUI camera view is being created.
    private var bundledObjectCandidateProvider: (any HatcheryObjectCandidateProviding)?
    private var didAttemptBundledObjectCandidateProviderLoad = false

    init() {
        injectedObjectCandidateProvider = nil
        loadsBundledObjectCandidateProvider = true
    }

    init(objectCandidateProvider: (any HatcheryObjectCandidateProviding)?) {
        injectedObjectCandidateProvider = objectCandidateProvider
        loadsBundledObjectCandidateProvider = false
    }

    func processLive(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryBoundaryDetection? {
        // `HatcheryVideoAnalyzer` invokes this from its dedicated serial
        // analyzer queue, so any bundled Core ML model is loaded off the main
        // actor and only when live analysis actually begins.
        let objectCandidateProvider = objectCandidateProviderForAnalysis()
        let imageSize = Self.orientedSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            orientation: orientation
        )
        stateLock.lock()
        if liveState.orientation != orientation || liveState.orientedImageSize != imageSize {
            liveState.generation &+= 1
            liveState.stable = nil
            liveState.pending = nil
            liveState.missedAnalyses = 0
            liveState.orientation = orientation
            liveState.orientedImageSize = imageSize
            // Bounding boxes are normalized in the oriented image's coordinate
            // space, so a cached result cannot survive a rotation or size swap.
            liveState.latestObjectDetection = nil
            liveState.lastObjectAnalysisAt = nil
        }
        let generation = liveState.generation
        let referenceBoundary = liveState.stable?.boundary ?? liveState.pending?.boundary
        let cachedObjectDetection = liveState.latestObjectDetection
        let shouldAnalyzeObject = objectCandidateProvider != nil
            && Self.shouldRefreshObjectDetection(
                lastAnalyzedAt: liveState.lastObjectAnalysisAt,
                now: ProcessInfo.processInfo.systemUptime
            )
        stateLock.unlock()

        let startedAt = ProcessInfo.processInfo.systemUptime
        var objectDetection = cachedObjectDetection
        if shouldAnalyzeObject {
            let refreshedObjectDetection = objectCandidateProvider?.detect(
                pixelBuffer: pixelBuffer,
                orientation: orientation
            )
            stateLock.lock()
            guard liveState.generation == generation else {
                stateLock.unlock()
                return nil
            }
            liveState.latestObjectDetection = refreshedObjectDetection
            liveState.lastObjectAnalysisAt = startedAt
            objectDetection = refreshedObjectDetection
            stateLock.unlock()
        }
        let analysis: Analysis
        do {
            let request = Self.rectangleRequest()
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )
            try handler.perform([request])
            analysis = Self.analysis(from: request.results ?? [], reference: referenceBoundary)
        } catch {
            logger.error("Live rectangle analysis failed")
            analysis = Analysis(candidates: [], observationCount: 0)
        }

        stateLock.lock()
        guard liveState.generation == generation else {
            stateLock.unlock()
            return nil
        }
        let candidate = Self.resolvedCandidate(
            objectDetection: objectDetection,
            rectangleCandidates: analysis.candidates
        )
        let update = updateLiveState(with: candidate, imageSize: imageSize)
        stateLock.unlock()

        let elapsedMilliseconds = Int(
            (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
        logger.debug(
            "Live analysis: latency_ms=\(elapsedMilliseconds, privacy: .public), observations=\(analysis.observationCount, privacy: .public), candidates=\(analysis.candidates.count, privacy: .public), state=\(update.status, privacy: .public)"
        )
        return update.detection
    }

    func detectStill(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> HatcheryBoundaryDetection? {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let objectCandidateProvider = objectCandidateProviderForAnalysis()
        let imageSize = Self.orientedSize(
            width: cgImage.width,
            height: cgImage.height,
            orientation: orientation
        )

        let objectDetection = objectCandidateProvider?.detect(
            cgImage: cgImage,
            orientation: orientation
        )
        let analysis: Analysis
        do {
            let request = Self.rectangleRequest()
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )
            try handler.perform([request])
            analysis = Self.analysis(from: request.results ?? [], reference: nil)
        } catch {
            logger.error("Still rectangle analysis failed")
            analysis = Analysis(candidates: [], observationCount: 0)
        }

        let candidate = Self.resolvedCandidate(
            objectDetection: objectDetection,
            rectangleCandidates: analysis.candidates
        )
        let elapsedMilliseconds = Int(
            (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
        logger.debug(
            "Still analysis: latency_ms=\(elapsedMilliseconds, privacy: .public), observations=\(analysis.observationCount, privacy: .public), candidates=\(analysis.candidates.count, privacy: .public), result=\(candidate == nil ? "fallback" : "detected", privacy: .public)"
        )

        guard let candidate else { return nil }
        return HatcheryBoundaryDetection(
            boundary: candidate.boundary,
            orientedImageSize: imageSize,
            confidence: candidate.confidence
        )
    }

    func reset() {
        stateLock.lock()
        let nextGeneration = liveState.generation &+ 1
        liveState = LiveState()
        liveState.generation = nextGeneration
        stateLock.unlock()
        logger.debug("Live detector state reset")
    }

    /// Feeds an already-normalized candidate through the same live stabilizer.
    /// Keeping this geometry-only seam also makes the scanner behavior
    /// deterministic to test without constructing camera sample buffers.
    func stabilize(
        _ candidate: HatcheryBoundaryDetection?
    ) -> HatcheryBoundaryDetection? {
        stateLock.lock()
        defer { stateLock.unlock() }

        let internalCandidate = candidate.map {
            Candidate(boundary: $0.boundary, confidence: $0.confidence, score: 0)
        }
        let imageSize = candidate?.orientedImageSize
            ?? liveState.stable?.orientedImageSize
            ?? liveState.orientedImageSize
            ?? .zero
        return updateLiveState(
            with: internalCandidate,
            imageSize: imageSize
        ).detection
    }

    private func updateLiveState(
        with candidate: Candidate?,
        imageSize: CGSize
    ) -> (detection: HatcheryBoundaryDetection?, status: String) {
        guard let candidate else {
            liveState.pending = nil
            guard let stable = liveState.stable else {
                return (nil, "no-candidate")
            }

            liveState.missedAnalyses += 1
            if liveState.missedAnalyses < Self.retainedMissCount {
                return (stable, "retained-after-miss")
            }

            liveState.stable = nil
            return (nil, "fallback-after-misses")
        }

        liveState.missedAnalyses = 0

        if let stable = liveState.stable,
           Self.maximumCornerDistance(stable.boundary, candidate.boundary) <= Self.maximumJump {
            let boundary = Self.smoothed(
                from: stable.boundary,
                toward: candidate.boundary,
                alpha: Self.smoothingAlpha
            )
            let detection = HatcheryBoundaryDetection(
                boundary: boundary,
                orientedImageSize: imageSize,
                confidence: Self.smoothed(
                    from: stable.confidence,
                    toward: candidate.confidence,
                    alpha: Self.smoothingAlpha
                )
            )
            liveState.stable = detection
            liveState.pending = nil
            return (detection, "tracking")
        }

        if var pending = liveState.pending,
           Self.maximumCornerDistance(pending.boundary, candidate.boundary) <= Self.maximumJump {
            pending.boundary = Self.smoothed(
                from: pending.boundary,
                toward: candidate.boundary,
                alpha: Self.smoothingAlpha
            )
            pending.confidence = Self.smoothed(
                from: pending.confidence,
                toward: candidate.confidence,
                alpha: Self.smoothingAlpha
            )
            pending.confirmations += 1
            liveState.pending = pending

            if pending.confirmations >= 2 {
                let detection = HatcheryBoundaryDetection(
                    boundary: pending.boundary,
                    orientedImageSize: imageSize,
                    confidence: pending.confidence
                )
                let replacedStable = liveState.stable != nil
                liveState.stable = detection
                liveState.pending = nil
                return (detection, replacedStable ? "jump-confirmed" : "initial-confirmed")
            }
        } else {
            liveState.pending = PendingDetection(
                boundary: candidate.boundary,
                confidence: candidate.confidence,
                confirmations: 1
            )
        }

        if let stable = liveState.stable {
            return (stable, "awaiting-jump-confirmation")
        }
        return (nil, "awaiting-initial-confirmation")
    }

    private static func rectangleRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 5
        request.minimumConfidence = 0.55
        request.minimumSize = 0.18
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1.0
        request.quadratureTolerance = 35
        return request
    }

    private static func analysis(
        from observations: [VNRectangleObservation],
        reference: HatcheryBoundary?
    ) -> Analysis {
        let candidates = observations.compactMap { observation in
            candidate(from: observation, reference: reference)
        }
        .sorted { $0.score > $1.score }

        return Analysis(candidates: candidates, observationCount: observations.count)
    }

    private static func candidate(
        from observation: VNRectangleObservation,
        reference: HatcheryBoundary?
    ) -> Candidate? {
        let boundary = HatcheryBoundary(
            topLeft: appPoint(from: observation.topLeft),
            topRight: appPoint(from: observation.topRight),
            bottomRight: appPoint(from: observation.bottomRight),
            bottomLeft: appPoint(from: observation.bottomLeft)
        )
        guard let score = score(
            boundary: boundary,
            confidence: observation.confidence,
            reference: reference
        ) else { return nil }

        return Candidate(
            boundary: boundary,
            confidence: observation.confidence,
            score: score
        )
    }

    /// A detected object identifies *which* region is likely to be the
    /// hatchery. A strongly aligned rectangle remains preferable because it
    /// carries the perspective corners used by later image rectification.
    static func resolvedCandidate(
        objectDetection: HatcheryObjectDetection?,
        rectangleCandidates: [Candidate]
    ) -> Candidate? {
        guard let objectDetection else {
            return rectangleCandidates.first
        }

        guard
            objectDetection.boundary.isValid,
            let objectScore = score(
                boundary: objectDetection.boundary,
                confidence: objectDetection.confidence,
                reference: nil
            )
        else {
            return rectangleCandidates.first
        }

        let strongestPerspectiveCandidate = rectangleCandidates
            .compactMap { candidate -> (candidate: Candidate, alignment: Double)? in
                guard let alignment = objectAlignmentScore(
                    candidate.boundary,
                    withObjectBoundary: objectDetection.boundary
                ) else {
                    return nil
                }
                return (candidate, alignment)
            }
            .max { lhs, rhs in
                if lhs.alignment == rhs.alignment {
                    return lhs.candidate.score < rhs.candidate.score
                }
                return lhs.alignment < rhs.alignment
            }

        if let strongestPerspectiveCandidate {
            return strongestPerspectiveCandidate.candidate
        }

        // Object observations are axis-aligned, but they still provide a valid
        // four-corner conservative guide when rectangle detection fails. Page
        // 8 remains the authoritative place for the user to refine the sand
        // outline before perspective correction and grid generation.
        return Candidate(
            boundary: objectDetection.boundary,
            confidence: objectDetection.confidence,
            score: objectScore
        )
    }

    /// Returns a score only for a perspective rectangle that plausibly describes
    /// the model's hatchery box. In particular, a tiny sign or label fully
    /// inside a large predicted hatchery is not a usable perspective plane.
    private static func objectAlignmentScore(
        _ rectangle: HatcheryBoundary,
        withObjectBoundary objectBoundary: HatcheryBoundary
    ) -> Double? {
        let rectangleBounds = boundingBox(of: rectangle)
        let objectBounds = boundingBox(of: objectBoundary)
        let intersection = rectangleBounds.intersection(objectBounds)
        guard !intersection.isNull, !intersection.isEmpty else { return nil }

        let rectangleArea = rectangleBounds.width * rectangleBounds.height
        let objectArea = objectBounds.width * objectBounds.height
        let intersectionArea = intersection.width * intersection.height
        guard rectangleArea > 0, objectArea > 0 else { return nil }

        let unionArea = rectangleArea + objectArea - intersectionArea
        let intersectionOverUnion = intersectionArea / unionArea
        let areaSimilarity = min(rectangleArea / objectArea, objectArea / rectangleArea)
        let rectangleCenter = CGPoint(x: rectangleBounds.midX, y: rectangleBounds.midY)
        let objectCenter = CGPoint(x: objectBounds.midX, y: objectBounds.midY)
        let centerDistance = hypot(
            rectangleCenter.x - objectCenter.x,
            rectangleCenter.y - objectCenter.y
        )
        let objectDiagonal = hypot(objectBounds.width, objectBounds.height)
        guard objectDiagonal > 0 else { return nil }
        let normalizedCenterDistance = centerDistance / objectDiagonal

        guard
            intersectionOverUnion >= 0.25,
            areaSimilarity >= 0.45,
            normalizedCenterDistance <= 0.25
        else {
            return nil
        }

        let centerAlignment = 1 - min(normalizedCenterDistance / 0.25, 1)
        return intersectionOverUnion * 0.55
            + areaSimilarity * 0.30
            + centerAlignment * 0.15
    }

    private static func boundingBox(of boundary: HatcheryBoundary) -> CGRect {
        let points = boundary.ordered
        let minimumX = points.map(\.x).min() ?? 0
        let maximumX = points.map(\.x).max() ?? 0
        let minimumY = points.map(\.y).min() ?? 0
        let maximumY = points.map(\.y).max() ?? 0
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    static func shouldRefreshObjectDetection(
        lastAnalyzedAt: TimeInterval?,
        now: TimeInterval
    ) -> Bool {
        guard now.isFinite else { return false }
        guard let lastAnalyzedAt else { return true }
        guard lastAnalyzedAt.isFinite else { return true }
        return now - lastAnalyzedAt
            >= objectAnalysisInterval - objectAnalysisTimingTolerance
    }

    /// Resolves an injected provider immediately, while a bundled model is
    /// loaded lazily from the caller's analysis path. Calls from the live
    /// scanner are serialized by `HatcheryVideoAnalyzer`; the lock keeps
    /// teardown and still-image work from observing partial state.
    private func objectCandidateProviderForAnalysis() -> (any HatcheryObjectCandidateProviding)? {
        if let injectedObjectCandidateProvider {
            return injectedObjectCandidateProvider
        }
        guard loadsBundledObjectCandidateProvider else { return nil }

        stateLock.lock()
        if didAttemptBundledObjectCandidateProviderLoad {
            let provider = bundledObjectCandidateProvider
            stateLock.unlock()
            return provider
        }
        didAttemptBundledObjectCandidateProviderLoad = true
        stateLock.unlock()

        let provider = HatcheryCoreMLObjectCandidateProvider.bundled()

        stateLock.lock()
        bundledObjectCandidateProvider = provider
        stateLock.unlock()
        return provider
    }

    static func score(
        boundary: HatcheryBoundary,
        confidence: Float,
        reference: HatcheryBoundary?
    ) -> Double? {
        guard boundary.isValid else { return nil }

        let area = polygonArea(boundary)
        guard area >= minimumArea, area <= maximumArea else { return nil }

        let center = boundary.ordered.reduce(CGPoint.zero) { partial, point in
            CGPoint(
                x: partial.x + point.cgPoint.x / 4,
                y: partial.y + point.cgPoint.y / 4
            )
        }
        let centerDistance = hypot(center.x - 0.5, center.y - 0.5)
        let centerScore = 1 - min(Double(centerDistance / hypot(0.5, 0.5)), 1)
        let sizeScore = (area - minimumArea) / (maximumArea - minimumArea)
        let continuityScore: Double
        if let reference {
            continuityScore = 1 - min(
                averageCornerDistance(reference, boundary) / maximumJump,
                1
            )
        } else {
            continuityScore = 0.5
        }

        return Double(confidence) * 0.45
            + sizeScore * 0.25
            + centerScore * 0.20
            + continuityScore * 0.10
    }

    static func appPoint(from visionPoint: CGPoint) -> NormalizedPoint {
        NormalizedPoint(
            x: Double(visionPoint.x),
            y: Double(1 - visionPoint.y)
        )
    }

    static func polygonArea(_ boundary: HatcheryBoundary) -> Double {
        let points = boundary.ordered
        let doubledArea = points.indices.reduce(0.0) { partial, index in
            let next = points[(index + 1) % points.count]
            return partial
                + points[index].x * next.y
                - next.x * points[index].y
        }
        return abs(doubledArea) * 0.5
    }

    static func averageCornerDistance(
        _ lhs: HatcheryBoundary,
        _ rhs: HatcheryBoundary
    ) -> Double {
        zip(lhs.ordered, rhs.ordered).reduce(0.0) { partial, pair in
            partial + hypot(pair.0.x - pair.1.x, pair.0.y - pair.1.y) / 4
        }
    }

    private static func maximumCornerDistance(
        _ lhs: HatcheryBoundary,
        _ rhs: HatcheryBoundary
    ) -> Double {
        zip(lhs.ordered, rhs.ordered).reduce(0.0) { currentMaximum, pair in
            max(currentMaximum, hypot(pair.0.x - pair.1.x, pair.0.y - pair.1.y))
        }
    }

    private static func smoothed(
        from current: HatcheryBoundary,
        toward next: HatcheryBoundary,
        alpha: Double
    ) -> HatcheryBoundary {
        HatcheryBoundary(
            topLeft: smoothed(from: current.topLeft, toward: next.topLeft, alpha: alpha),
            topRight: smoothed(from: current.topRight, toward: next.topRight, alpha: alpha),
            bottomRight: smoothed(
                from: current.bottomRight,
                toward: next.bottomRight,
                alpha: alpha
            ),
            bottomLeft: smoothed(
                from: current.bottomLeft,
                toward: next.bottomLeft,
                alpha: alpha
            )
        )
    }

    private static func smoothed(
        from current: NormalizedPoint,
        toward next: NormalizedPoint,
        alpha: Double
    ) -> NormalizedPoint {
        NormalizedPoint(
            x: current.x + (next.x - current.x) * alpha,
            y: current.y + (next.y - current.y) * alpha
        )
    }

    private static func smoothed(from current: Float, toward next: Float, alpha: Double) -> Float {
        current + (next - current) * Float(alpha)
    }

    static func orientedSize(
        width: Int,
        height: Int,
        orientation: CGImagePropertyOrientation
    ) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }
}
