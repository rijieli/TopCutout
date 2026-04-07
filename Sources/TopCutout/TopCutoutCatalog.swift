import UIKit

/// Resolves generated screen and top cutout metadata for the current iPhone model.
///
/// `TopCutoutCatalog` is the main runtime entry point for the package. It reads the current
/// model identifier, matches it against the generated device catalog, and exposes the resulting
/// ``ScreenInfo`` and ``TopCutoutInfo`` values.
///
/// On Simulator, lookup prefers `SIMULATOR_MODEL_IDENTIFIER`. On device, lookup uses `uname`.
public enum TopCutoutCatalog {
    /// Screen metadata for the current device.
    ///
    /// This value is resolved once from the current model identifier and returns the generated
    /// catalog entry for that device. When the current iPhone model identifier is not present,
    /// the resolver falls back to the nearest generated iPhone screen size.
    ///
    /// - Returns: The matched or nearest-size screen metadata, or `nil` when no safe match can be
    ///   resolved.
    public static let screen: ScreenInfo? = {
        screenInfo(for: currentModelIdentifier())
    }()

    /// Top cutout metadata for the current device.
    ///
    /// This is a convenience accessor for `TopCutoutCatalog.screen?.topCutout`.
    ///
    /// - Returns: The matched or nearest-size top cutout metadata, or `nil` when no safe match can
    ///   be resolved.
    public static let current: TopCutoutInfo? = {
        screen?.topCutout
    }()

    private static func currentModelIdentifier() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !sim.isEmpty {
            return sim
        }

        var systemInfo = utsname()
        uname(&systemInfo)

        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    private struct RuntimeScreenMetrics {
        let pixels: CGSize
        let points: CGSize
        let scale: CGFloat
    }

    private static func screenInfo(for modelIdentifier: String) -> ScreenInfo? {
        if let exactMatch = Device(rawValue: modelIdentifier)?.screen {
            return exactMatch
        }

        guard UIDevice.current.userInterfaceIdiom == .phone,
              let currentMetrics = currentScreenMetrics(),
              let nearestDevice = nearestDevice(for: currentMetrics) else {
            return nil
        }

        var screenInfo = nearestDevice.screen
        screenInfo.markResolvedByScreenSize()
        return screenInfo
    }

    private static func currentScreenMetrics() -> RuntimeScreenMetrics? {
        let screen = UIScreen.main
        let points = normalized(screen.bounds.size)
        guard points.width > 0, points.height > 0 else {
            return nil
        }

        let nativePixels = normalized(screen.nativeBounds.size)
        let pixels: CGSize
        if nativePixels.width > 0, nativePixels.height > 0 {
            pixels = nativePixels
        } else {
            pixels = CGSize(
                width: points.width * screen.scale,
                height: points.height * screen.scale
            )
        }

        return RuntimeScreenMetrics(
            pixels: pixels,
            points: points,
            scale: screen.scale
        )
    }

    private static func nearestDevice(for currentMetrics: RuntimeScreenMetrics) -> Device? {
        Device.allCases.enumerated().min { lhs, rhs in
            let lhsScore = sizeMatchScore(for: lhs.element.screen, currentMetrics: currentMetrics)
            let rhsScore = sizeMatchScore(for: rhs.element.screen, currentMetrics: currentMetrics)

            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }

            // Prefer newer catalog entries when multiple devices share the same dimensions.
            return lhs.offset > rhs.offset
        }?.element
    }

    private static func sizeMatchScore(
        for screenInfo: ScreenInfo,
        currentMetrics: RuntimeScreenMetrics
    ) -> CGSizeMatchScore {
        CGSizeMatchScore(
            pointDistanceSquared: squaredDistance(
                normalized(screenInfo.points),
                currentMetrics.points
            ),
            pixelDistanceSquared: squaredDistance(
                normalized(screenInfo.pixels),
                currentMetrics.pixels
            ),
            scaleDistanceSquared: squared(currentMetrics.scale - screenInfo.scale)
        )
    }

    private static func normalized(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(size.width, size.height),
            height: max(size.width, size.height)
        )
    }

    private static func squaredDistance(_ lhs: CGSize, _ rhs: CGSize) -> CGFloat {
        squared(lhs.width - rhs.width) + squared(lhs.height - rhs.height)
    }

    private static func squared(_ value: CGFloat) -> CGFloat {
        value * value
    }
}

private struct CGSizeMatchScore: Comparable {
    let pointDistanceSquared: CGFloat
    let pixelDistanceSquared: CGFloat
    let scaleDistanceSquared: CGFloat

    static func < (lhs: CGSizeMatchScore, rhs: CGSizeMatchScore) -> Bool {
        if lhs.pointDistanceSquared != rhs.pointDistanceSquared {
            return lhs.pointDistanceSquared < rhs.pointDistanceSquared
        }

        if lhs.pixelDistanceSquared != rhs.pixelDistanceSquared {
            return lhs.pixelDistanceSquared < rhs.pixelDistanceSquared
        }

        return lhs.scaleDistanceSquared < rhs.scaleDistanceSquared
    }
}
