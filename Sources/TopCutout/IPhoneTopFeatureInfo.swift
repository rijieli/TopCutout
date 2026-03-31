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

    public func rect(in bounds: CGRect) -> CGRect? {
        guard let size, let paddingTop else {
            return nil
        }

        return CGRect(
            x: (bounds.width - size.width) * 0.5,
            y: paddingTop,
            width: size.width,
            height: size.height
        )
    }

    public func occupiedTopBand(in bounds: CGRect) -> CGRect? {
        guard let size, let paddingTop else {
            return nil
        }

        return CGRect(x: 0, y: 0, width: bounds.width, height: paddingTop + size.height)
    }

    public func leadingEarRect(in bounds: CGRect) -> CGRect? {
        guard let cutout = rect(in: bounds),
              let size,
              let paddingTop else {
            return nil
        }

        return CGRect(
            x: 0,
            y: 0,
            width: max(0, cutout.minX),
            height: paddingTop + size.height
        )
    }

    public func trailingEarRect(in bounds: CGRect) -> CGRect? {
        guard let cutout = rect(in: bounds),
              let size,
              let paddingTop else {
            return nil
        }

        return CGRect(
            x: cutout.maxX,
            y: 0,
            width: max(0, bounds.width - cutout.maxX),
            height: paddingTop + size.height
        )
    }

    public func recommendedButtonCenters(
        in bounds: CGRect,
        buttonSize: CGSize,
        sidePadding: CGFloat = 8
    ) -> (leading: CGPoint, trailing: CGPoint)? {
        guard let size, let paddingTop else {
            return nil
        }

        let left = leadingEarRect(in: bounds)?.insetBy(dx: sidePadding, dy: 0)
        let right = trailingEarRect(in: bounds)?.insetBy(dx: sidePadding, dy: 0)

        guard let left,
              let right,
              left.width >= buttonSize.width,
              right.width >= buttonSize.width else {
            return nil
        }

        let centerY = (paddingTop + size.height) * 0.5

        let leading = CGPoint(
            x: left.maxX - buttonSize.width * 0.5,
            y: centerY
        )

        let trailing = CGPoint(
            x: right.minX + buttonSize.width * 0.5,
            y: centerY
        )

        return (leading, trailing)
    }
}
