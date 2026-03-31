import UIKit

extension TopCutoutCatalog {
    public struct ScreenInfo: Equatable, Sendable {
        public let cornerRadiusPoints: CGFloat?
        public let dpi: Int?
        public let pixels: CGSize
        public let points: CGSize
        public let scale: CGFloat
        public let topCutout: TopCutoutInfo

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
