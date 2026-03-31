import UIKit

extension TopCutoutCatalog {
    /// Display metadata associated with a generated device entry.
    ///
    /// `ScreenInfo` combines general screen characteristics with the corresponding
    /// ``TopCutoutInfo`` so callers can make both device-level and layout-level decisions from a
    /// single value.
    public struct ScreenInfo: Equatable, Sendable {
        /// The display corner radius in points, when known.
        public let cornerRadiusPoints: CGFloat?
        /// The display density in pixels per inch, when known.
        public let dpi: Int?
        /// The native screen resolution in pixels.
        public let pixels: CGSize
        /// The logical screen size in points.
        public let points: CGSize
        /// The display scale factor.
        public let scale: CGFloat
        /// Top cutout metadata for the screen.
        public let topCutout: TopCutoutInfo

        /// Creates a screen metadata value.
        ///
        /// - Parameters:
        ///   - cornerRadiusPoints: The display corner radius in points, when known.
        ///   - dpi: The display density in pixels per inch, when known.
        ///   - pixels: The native screen resolution in pixels.
        ///   - points: The logical screen size in points.
        ///   - scale: The display scale factor.
        ///   - topCutout: Top cutout metadata for the screen.
        public init(
            cornerRadiusPoints: CGFloat?,
            dpi: Int?,
            pixels: CGSize,
            points: CGSize,
            scale: CGFloat,
            topCutout: TopCutoutInfo
        ) {
            self.cornerRadiusPoints = cornerRadiusPoints
            self.dpi = dpi
            self.pixels = pixels
            self.points = points
            self.scale = scale
            self.topCutout = topCutout
        }
    }
}
