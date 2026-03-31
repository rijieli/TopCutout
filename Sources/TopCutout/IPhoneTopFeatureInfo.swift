import UIKit

public enum IPhoneTopFeatureKind: String, Equatable, Sendable {
    case none
    case notch
    case dynamicIsland
}

public struct IPhoneTopFeatureInfo: Equatable, Sendable {
    public let kind: IPhoneTopFeatureKind
    public let geometryAvailable: Bool
    public let curveAvailable: Bool
    public let size: CGSize?
    public let paddingTop: CGFloat?

    public init(
        kind: IPhoneTopFeatureKind,
        geometryAvailable: Bool,
        curveAvailable: Bool,
        size: CGSize?,
        paddingTop: CGFloat?
    ) {
        self.kind = kind
        self.geometryAvailable = geometryAvailable
        self.curveAvailable = curveAvailable
        self.size = size
        self.paddingTop = paddingTop
    }
}
