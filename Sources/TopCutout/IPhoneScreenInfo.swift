import UIKit

public struct IPhoneScreenInfo: Equatable, Sendable {
    public let cornerRadiusPoints: CGFloat?
    public let dpi: Int?
    public let pixels: CGSize
    public let points: CGSize
    public let scale: CGFloat
    public let topFeature: IPhoneTopFeatureInfo

    public init(
        cornerRadiusPoints: CGFloat?,
        dpi: Int?,
        pixels: CGSize,
        points: CGSize,
        scale: CGFloat,
        topFeature: IPhoneTopFeatureInfo
    ) {
        self.cornerRadiusPoints = cornerRadiusPoints
        self.dpi = dpi
        self.pixels = pixels
        self.points = points
        self.scale = scale
        self.topFeature = topFeature
    }
}
