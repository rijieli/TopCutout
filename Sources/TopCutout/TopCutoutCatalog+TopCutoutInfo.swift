import UIKit

extension TopCutoutCatalog {
    /// The top cutout style present on a screen.
    public enum TopCutoutKind: String, Equatable, Sendable {
        /// The screen has no top cutout.
        case none
        /// The screen uses a classic notch layout.
        case notch
        /// The screen uses a Dynamic Island layout.
        case dynamicIsland
    }

    /// Top cutout metadata associated with a screen.
    ///
    /// Use this type when layout decisions depend on the actual cutout geometry rather than only
    /// safe-area insets. Geometry values are expressed in points and can be projected into any
    /// caller-provided bounds using the helper methods below.
    public struct TopCutoutInfo: Equatable, Sendable {
        /// The detected top cutout style.
        public let kind: TopCutoutKind
        /// Indicates whether `size` and `paddingTop` contain generated geometry.
        ///
        /// When this is `false`, the device may still report a cutout `kind`, but the precise
        /// geometry helpers return `nil`.
        public let geometryAvailable: Bool
        /// Indicates whether a precomputed sensor housing outline is available for this device family.
        public let curveAvailable: Bool
        /// The cutout size in points.
        ///
        /// This is `nil` when exact geometry is unavailable.
        public let size: CGSize?
        /// The distance from the top edge of the screen to the top edge of the cutout, in points.
        ///
        /// This is `nil` when exact geometry is unavailable.
        public let paddingTop: CGFloat?

        /// Creates a top cutout metadata value.
        ///
        /// - Parameters:
        ///   - kind: The detected top cutout style.
        ///   - geometryAvailable: Whether cutout geometry values are available.
        ///   - curveAvailable: Whether a precomputed sensor housing outline is available.
        ///   - size: The cutout size in points, when known.
        ///   - paddingTop: The offset from the top screen edge to the cutout, when known.
        public init(
            kind: TopCutoutKind,
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

        /// Returns the cutout rectangle projected into the provided bounds.
        ///
        /// The cutout is horizontally centered within `bounds`, and its vertical origin is
        /// `paddingTop` measured from `bounds.minY`.
        ///
        /// - Parameter bounds: The screen-aligned bounds to project the cutout into.
        /// - Returns: The cutout rectangle, or `nil` when geometry data is unavailable.
        public func rect(in bounds: CGRect) -> CGRect? {
            guard let size, let paddingTop else {
                return nil
            }

            return CGRect(
                x: bounds.minX + (bounds.width - size.width) * 0.5,
                y: bounds.minY + paddingTop,
                width: size.width,
                height: size.height
            )
        }

        /// Returns the top band occupied by the cutout and the space above it.
        ///
        /// This is often the region that should remain clear for top-edge chrome or custom overlays.
        ///
        /// - Parameter bounds: The screen-aligned bounds to project the cutout into.
        /// - Returns: The occupied top band, or `nil` when geometry data is unavailable.
        public func occupiedTopBand(in bounds: CGRect) -> CGRect? {
            guard let size, let paddingTop else {
                return nil
            }

            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: paddingTop + size.height
            )
        }

        /// Returns the usable top-side region before the cutout.
        ///
        /// The returned rect uses physical left-to-right screen coordinates. It does not mirror for
        /// right-to-left layout direction.
        ///
        /// - Parameter bounds: The screen-aligned bounds to project the cutout into.
        /// - Returns: The leading side region, or `nil` when geometry data is unavailable.
        public func leadingEarRect(in bounds: CGRect) -> CGRect? {
            guard let cutout = rect(in: bounds),
                  let size,
                  let paddingTop else {
                return nil
            }

            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: max(0, cutout.minX - bounds.minX),
                height: paddingTop + size.height
            )
        }

        /// Returns the usable top-side region after the cutout.
        ///
        /// The returned rect uses physical left-to-right screen coordinates. It does not mirror for
        /// right-to-left layout direction.
        ///
        /// - Parameter bounds: The screen-aligned bounds to project the cutout into.
        /// - Returns: The trailing side region, or `nil` when geometry data is unavailable.
        public func trailingEarRect(in bounds: CGRect) -> CGRect? {
            guard let cutout = rect(in: bounds),
                  let size,
                  let paddingTop else {
                return nil
            }

            return CGRect(
                x: cutout.maxX,
                y: bounds.minY,
                width: max(0, bounds.maxX - cutout.maxX),
                height: paddingTop + size.height
            )
        }

        /// Returns symmetric button centers that fit within both side regions.
        ///
        /// This is a convenience helper for placing small controls in the free space on each side
        /// of a notch or Dynamic Island. The result is `nil` unless both sides can fit the provided
        /// `buttonSize` after `sidePadding` has been applied.
        ///
        /// - Parameters:
        ///   - bounds: The screen-aligned bounds to project the cutout into.
        ///   - buttonSize: The button size that must fit in each side region.
        ///   - sidePadding: Extra horizontal inset applied to each side region before placement.
        /// - Returns: Leading and trailing button centers, or `nil` when geometry is unavailable or space is insufficient.
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

            let centerY = bounds.minY + (paddingTop + size.height) * 0.5

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
}
