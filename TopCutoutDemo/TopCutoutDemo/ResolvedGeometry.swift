//
//  ResolvedGeometry.swift
//  TopCutoutDemo
//
//  Created by Roger on 2026/3/31.
//

import SwiftUI
import TopCutout

struct ResolvedGeometry {
    let topCutout: TopCutoutCatalog.TopCutoutInfo
    let screenInfo: TopCutoutCatalog.ScreenInfo
    let source: String
    let modelIdentifier: String
}

struct TopCutoutCatalogProbeReport: Encodable {
    let deviceName: String
    let modelIdentifier: String
    let screenSize: ProbeSize
    let safeAreaTop: Double
    let displayConfigurationClass: String?
    let displayConfigurationDescription: String?
    let displayInfoProvider: ProbeDisplayInfoProvider?
    let exclusionRect: ProbeRect?
    let inferredGeometry: ProbeGeometry?
    let resolvedGeometry: ProbeGeometry?
    let resolvedSource: String?
    let matchesResolvedGeometry: Bool?

    var logKey: String {
        let rectKey = exclusionRect.map { "\($0.x),\($0.y),\($0.width),\($0.height)" } ?? "none"
        return "\(modelIdentifier)|\(screenSize.width)|\(screenSize.height)|\(safeAreaTop)|\(rectKey)|\(resolvedSource ?? "none")"
    }

    var prettyJSONString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{ \"error\": \"Failed to encode debug report\" }"
        }

        return string
    }

    static func make(
        screenSize: CGSize,
        safeAreaTop: CGFloat,
        resolved: ResolvedGeometry?
    ) -> TopCutoutCatalogProbeReport {
        let modelIdentifier = TopCutoutDemoProbe.currentModelIdentifier()
        let displayConfiguration = TopCutoutCatalogProbe.displayConfiguration
        let displayInfoProvider = TopCutoutCatalogProbe.displayInfoProvider
        let exclusionRect = TopCutoutCatalogProbe.exclusionRect.map(ProbeRect.init)
        let inferredGeometry = TopCutoutCatalogProbe.exclusionRect.map { ProbeGeometry(rect: $0) }
        let resolvedGeometry = resolved.map { ProbeGeometry(topCutout: $0.topCutout) }
        let matchesResolvedGeometry = inferredGeometry.flatMap { inferred in
            resolvedGeometry.map { inferred.matches($0) }
        }

        return TopCutoutCatalogProbeReport(
            deviceName: TopCutoutCatalogProbe.deviceName,
            modelIdentifier: modelIdentifier,
            screenSize: ProbeSize(size: screenSize),
            safeAreaTop: Self.probeValue(safeAreaTop),
            displayConfigurationClass: displayConfiguration.map { String(describing: type(of: $0)) },
            displayConfigurationDescription: displayConfiguration.map { String(describing: $0) },
            displayInfoProvider: displayInfoProvider.map(ProbeDisplayInfoProvider.init),
            exclusionRect: exclusionRect,
            inferredGeometry: inferredGeometry,
            resolvedGeometry: resolvedGeometry,
            resolvedSource: resolved?.source,
            matchesResolvedGeometry: matchesResolvedGeometry
        )
    }

    static func probeValue(_ value: CGFloat) -> Double {
        let raw = Double(value)
        let rounded = raw.rounded()
        if abs(raw - rounded) < 0.000_1 {
            return rounded
        }

        return raw
    }
}

struct ProbeInsets: Encodable {
    let top: Double
    let left: Double
    let bottom: Double
    let right: Double

    init?(_ value: Any?) {
        if let insets = value as? UIEdgeInsets {
            self.init(insets)
            return
        }

        if let boxed = value as? NSValue {
            self.init(boxed.uiEdgeInsetsValue)
            return
        }

        return nil
    }

    init(_ insets: UIEdgeInsets) {
        top = TopCutoutCatalogProbeReport.probeValue(insets.top)
        left = TopCutoutCatalogProbeReport.probeValue(insets.left)
        bottom = TopCutoutCatalogProbeReport.probeValue(insets.bottom)
        right = TopCutoutCatalogProbeReport.probeValue(insets.right)
    }
}

struct ProbeSize: Encodable {
    let width: Double
    let height: Double

    init(size: CGSize) {
        width = TopCutoutCatalogProbeReport.probeValue(size.width)
        height = TopCutoutCatalogProbeReport.probeValue(size.height)
    }
}

struct ProbeGeometry: Encodable {
    let style: String
    let width: Double
    let height: Double
    let topInset: Double

    init(topCutout: TopCutoutCatalog.TopCutoutInfo) {
        style = topCutout.kind.rawValue
        width = TopCutoutCatalogProbeReport.probeValue(topCutout.size?.width ?? 0)
        height = TopCutoutCatalogProbeReport.probeValue(topCutout.size?.height ?? 0)
        topInset = TopCutoutCatalogProbeReport.probeValue(topCutout.paddingTop ?? 0)
    }

    init(rect: CGRect) {
        let inferredKind: TopCutoutCatalog.TopCutoutKind
        if rect.minY > 0.5 {
            inferredKind = .dynamicIsland
        } else {
            inferredKind = .notch
        }

        style = inferredKind.rawValue
        width = TopCutoutCatalogProbeReport.probeValue(rect.width)
        height = TopCutoutCatalogProbeReport.probeValue(rect.height)
        topInset = TopCutoutCatalogProbeReport.probeValue(rect.minY)
    }

    func matches(_ other: ProbeGeometry) -> Bool {
        style == other.style &&
        abs(width - other.width) < 0.000_1 &&
        abs(height - other.height) < 0.000_1 &&
        abs(topInset - other.topInset) < 0.000_1
    }
}

enum TopCutoutCatalogProbe {
    static var deviceName: String {
        let environment = ProcessInfo.processInfo.environment

        if let name = environment["SIMULATOR_DEVICE_NAME"], !name.isEmpty {
            return name
        }

        return UIDevice.current.name
    }

    static var exclusionRect: CGRect? = {
        let screen = UIScreen.main

        guard let exclusionArea = screen.value(forKey: "_" + "exclusion" + "Area") as? NSObject,
              let rectValue = exclusionArea.value(forKey: "rect") else {
            print("[TopCutoutDemo] Exclusion area not available; returning nil")
            return nil
        }

        if let rect = rectValue as? CGRect {
            print("[TopCutoutDemo] Retrieved exclusionRect: \(rect)")
            return rect
        }

        if let value = rectValue as? NSValue {
            let rect = value.cgRectValue
            print("[TopCutoutDemo] Retrieved exclusionRect: \(rect)")
            return rect
        }

        print("[TopCutoutDemo] Exclusion area rect had unexpected type: \(type(of: rectValue))")
        return nil
    }()

    static var displayConfiguration: NSObject? = {
        let screen = UIScreen.main
        return screen.value(forKey: "__displayConfiguration") as? NSObject
    }()

    static var displayInfoProvider: NSObject? = {
        let screen = UIScreen.main
        return screen.value(forKey: "_displayInfoProvider") as? NSObject
    }()

}

enum TopCutoutDemoProbe {
    static func currentModelIdentifier() -> String {
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
}

extension TopCutoutCatalogProbeReport {
    var exclusionSummary: String {
        guard let exclusionRect else {
            return "Unavailable"
        }

        return "x \(format(exclusionRect.x)) y \(format(exclusionRect.y)) w \(format(exclusionRect.width)) h \(format(exclusionRect.height))"
    }

    var inferredGeometrySummary: String {
        guard let inferredGeometry else {
            return "Unavailable"
        }

        return "\(inferredGeometry.style) \(format(inferredGeometry.width)) x \(format(inferredGeometry.height)) @ \(format(inferredGeometry.topInset))"
    }

    private func format(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.000_1 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
    }
}

struct UnresolvedPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No cutout geometry resolved")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("The current device was not matched by the generated device table, so no supported cutout shape was resolved.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.74))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        )
    }
}
