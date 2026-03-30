//
//  TopCutoutStyle.swift
//  TopCutout
//
//  Created by Roger on 2026/3/30.
//


import UIKit

public enum TopCutoutStyle: String, Sendable {
    case wideNotch
    case narrowNotch
    case dynamicIsland
}

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

public enum IPhoneTopCutoutCatalog {
    // MARK: - Public API

    public static var current: TopCutoutGeometry? {
        geometry(for: currentModelIdentifier())
    }

    public static func currentModelIdentifier() -> String {
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

    public static func geometry(for modelIdentifier: String) -> TopCutoutGeometry? {
        map[modelIdentifier]
    }

    /// Optional fallback when you want something for unknown future devices.
    /// This is intentionally conservative.
    public static func heuristicGeometry(
        screenSize: CGSize,
        safeAreaTop: CGFloat
    ) -> TopCutoutGeometry? {
        let width = Int(screenSize.width.rounded())
        let top = Int(safeAreaTop.rounded())

        switch (width, top) {
        case (375, 44):
            return wideNotch375
        case (414, 44):
            return wideNotch414
        case (390, 47):
            return narrowNotch390
        case (428, 47), (428, 53):
            return narrowNotch428
        case (375, 50):
            return narrowNotch375MiniEstimate
        case (393, 59):
            return dynamicIsland393
        case (430, 59):
            return dynamicIsland430
        case (402, 62):
            return dynamicIsland402
        case (440, 62):
            return dynamicIsland440
        case (420, 68):
            return dynamicIsland420
        default:
            return nil
        }
    }

    // MARK: - Geometry families

    private static let wideNotch375 = TopCutoutGeometry(
        style: .wideNotch,
        size: CGSize(width: 209, height: 30),
        topInset: 0
    )

    private static let wideNotch414 = TopCutoutGeometry(
        style: .wideNotch,
        size: CGSize(width: 210, height: 30),
        topInset: 0
    )

    private static let wideNotch390 = TopCutoutGeometry(
        style: .wideNotch,
        size: CGSize(width: 210, height: 32),
        topInset: 0
    )

    private static let wideNotch375Mini = TopCutoutGeometry(
        style: .wideNotch,
        size: CGSize(width: 227, height: 34),
        topInset: 0
    )

    private static let narrowNotch390 = TopCutoutGeometry(
        style: .narrowNotch,
        size: CGSize(width: 162, height: 33),
        topInset: 0
    )

    private static let narrowNotch428 = TopCutoutGeometry(
        style: .narrowNotch,
        size: CGSize(width: 162, height: 33),
        topInset: 0
    )

    /// Estimated from the same physical “smaller notch” change as the 13 family,
    /// adjusted to the mini’s logical PPI class.
    private static let narrowNotch375MiniEstimate = TopCutoutGeometry(
        style: .narrowNotch,
        size: CGSize(width: 168, height: 34),
        topInset: 0
    )

    private static let dynamicIsland393 = TopCutoutGeometry(
        style: .dynamicIsland,
        size: CGSize(width: 125, height: 37),
        topInset: 11
    )

    private static let dynamicIsland430 = TopCutoutGeometry(
        style: .dynamicIsland,
        size: CGSize(width: 125, height: 37),
        topInset: 11
    )

    private static let dynamicIsland402 = TopCutoutGeometry(
        style: .dynamicIsland,
        size: CGSize(width: 125, height: 37),
        topInset: 14
    )

    private static let dynamicIsland440 = TopCutoutGeometry(
        style: .dynamicIsland,
        size: CGSize(width: 125, height: 37),
        topInset: 14
    )

    private static let dynamicIsland420 = TopCutoutGeometry(
        style: .dynamicIsland,
        size: CGSize(width: 125, height: 37),
        topInset: 14
    )

    // MARK: - Identifier map

    private static let map: [String: TopCutoutGeometry] = {
        var result: [String: TopCutoutGeometry] = [:]

        func assign(_ ids: [String], _ geometry: TopCutoutGeometry) {
            ids.forEach { result[$0] = geometry }
        }

        // iPhone X / XS / 11 Pro
        assign([
            "iPhone10,3", "iPhone10,6", // iPhone X
            "iPhone11,2",               // iPhone XS
            "iPhone12,3"                // iPhone 11 Pro
        ], wideNotch375)

        // iPhone XR / XS Max / 11 / 11 Pro Max
        assign([
            "iPhone11,8",               // iPhone XR
            "iPhone11,4", "iPhone11,6", // iPhone XS Max
            "iPhone12,1",               // iPhone 11
            "iPhone12,5"                // iPhone 11 Pro Max
        ], wideNotch414)

        // iPhone 12 / 12 Pro
        assign([
            "iPhone13,2", // iPhone 12
            "iPhone13,3"  // iPhone 12 Pro
        ], wideNotch390)

        // iPhone 12 Pro Max
        assign([
            "iPhone13,4"
        ], TopCutoutGeometry(
            style: .wideNotch,
            size: CGSize(width: 210, height: 32),
            topInset: 0
        ))

        // iPhone 12 mini
        assign([
            "iPhone13,1"
        ], wideNotch375Mini)

        // iPhone 13 / 13 Pro / 14 / 16e / 17e
        assign([
            "iPhone14,5", // iPhone 13
            "iPhone14,2", // iPhone 13 Pro
            "iPhone14,7", // iPhone 14
            "iPhone17,5", // iPhone 16e
            "iPhone18,5"  // iPhone 17e
        ], narrowNotch390)

        // iPhone 13 Pro Max / 14 Plus
        assign([
            "iPhone14,3", // iPhone 13 Pro Max
            "iPhone14,8"  // iPhone 14 Plus
        ], narrowNotch428)

        // iPhone 13 mini
        assign([
            "iPhone14,4"
        ], narrowNotch375MiniEstimate)

        // iPhone 14 Pro / 15 / 15 Pro / 16
        assign([
            "iPhone15,2", // iPhone 14 Pro
            "iPhone15,4", // iPhone 15
            "iPhone16,1", // iPhone 15 Pro
            "iPhone17,3"  // iPhone 16
        ], dynamicIsland393)

        // iPhone 14 Pro Max / 15 Plus / 15 Pro Max / 16 Plus
        assign([
            "iPhone15,3", // iPhone 14 Pro Max
            "iPhone15,5", // iPhone 15 Plus
            "iPhone16,2", // iPhone 15 Pro Max
            "iPhone17,4"  // iPhone 16 Plus
        ], dynamicIsland430)

        // iPhone 16 Pro / 17 / 17 Pro
        assign([
            "iPhone17,1", // iPhone 16 Pro
            "iPhone18,3", // iPhone 17
            "iPhone18,1"  // iPhone 17 Pro
        ], dynamicIsland402)

        // iPhone 16 Pro Max / 17 Pro Max
        assign([
            "iPhone17,2", // iPhone 16 Pro Max
            "iPhone18,2"  // iPhone 17 Pro Max
        ], dynamicIsland440)

        // iPhone Air
        assign([
            "iPhone18,4"
        ], dynamicIsland420)

        return result
    }()
}
