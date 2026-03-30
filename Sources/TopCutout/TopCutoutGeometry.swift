import UIKit

public struct TopCutoutGeometry: Equatable, Sendable {
    public let style: TopCutoutStyle

    /// Size of the visible top cutout / island in points, portrait.
    public let size: CGSize

    /// Distance from the top screen edge to the cutout in points.
    /// Notch devices are generally `0`.
    public let topInset: CGFloat

    public init(style: TopCutoutStyle, size: CGSize, topInset: CGFloat) {
        self.style = style
        self.size = size
        self.topInset = topInset
    }

    /// Portrait cutout rect centered horizontally in `bounds`.
    public func rect(in bounds: CGRect) -> CGRect {
        CGRect(
            x: (bounds.width - size.width) * 0.5,
            y: topInset,
            width: size.width,
            height: size.height
        )
    }

    /// The full top occupied band, from the top edge down to the bottom of the cutout.
    public func occupiedTopBand(in bounds: CGRect) -> CGRect {
        CGRect(x: 0, y: 0, width: bounds.width, height: topInset + size.height)
    }

    /// Approximate free region to the left of the cutout inside the top band.
    public func leadingEarRect(in bounds: CGRect) -> CGRect {
        let cutout = rect(in: bounds)
        return CGRect(
            x: 0,
            y: 0,
            width: max(0, cutout.minX),
            height: topInset + size.height
        )
    }

    /// Approximate free region to the right of the cutout inside the top band.
    public func trailingEarRect(in bounds: CGRect) -> CGRect {
        let cutout = rect(in: bounds)
        return CGRect(
            x: cutout.maxX,
            y: 0,
            width: max(0, bounds.width - cutout.maxX),
            height: topInset + size.height
        )
    }

    /// A helper if you want quick symmetric button centers around the cutout.
    public func recommendedButtonCenters(
        in bounds: CGRect,
        buttonSize: CGSize,
        sidePadding: CGFloat = 8
    ) -> (leading: CGPoint, trailing: CGPoint)? {
        let left = leadingEarRect(in: bounds).insetBy(dx: sidePadding, dy: 0)
        let right = trailingEarRect(in: bounds).insetBy(dx: sidePadding, dy: 0)

        guard left.width >= buttonSize.width, right.width >= buttonSize.width else {
            return nil
        }

        let centerY = (topInset + size.height) * 0.5

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
