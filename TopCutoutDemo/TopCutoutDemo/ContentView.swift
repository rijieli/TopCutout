//
//  ContentView.swift
//  TopCutoutDemo
//
//  Created by Roger on 2026/3/30.
//

import SwiftUI
import TopCutout
import UIKit

struct ContentView: View {
    @State private var isGlowing = false
    @State private var copyFeedback = "Copy Debug JSON"
    @State private var lastLoggedReportKey: String?

    var body: some View {
        GeometryReader { proxy in
            let resolved = resolvedGeometry(
                screenSize: proxy.size,
                safeAreaTop: proxy.safeAreaInsets.top
            )
            let debugReport = TopCutoutCatalogProbeReport.make(
                screenSize: proxy.size,
                safeAreaTop: proxy.safeAreaInsets.top,
                resolved: resolved
            )
            let cutoutBottom = resolved.flatMap { resolved in
                guard let size = resolved.topCutout.size,
                      let paddingTop = resolved.topCutout.paddingTop else {
                    return nil
                }
                return paddingTop + size.height
            } ?? proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                DemoBackdrop()

                if let resolved {
                    LiveCutoutOverlay(
                        topCutout: resolved.topCutout,
                        isGlowing: isGlowing
                    )
                    .allowsHitTesting(false)
                }

                if let exclusionRect = debugReport.exclusionRect {
                    DebugExclusionOverlay(rect: exclusionRect)
                        .allowsHitTesting(false)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        Spacer()
                            .frame(height: max(170, cutoutBottom + 108))

                        HeaderBlock()

                        if let resolved {
                            InfoPanel(resolved: resolved)
                        } else {
                            UnresolvedPanel()
                        }

                        DebugProbePanel(
                            report: debugReport,
                            copyFeedback: copyFeedback,
                            onCopy: { copyDebugReport(debugReport) }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .ignoresSafeArea()
            .task(id: debugReport.logKey) {
                logDebugReportIfNeeded(debugReport)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }

    private func resolvedGeometry(screenSize _: CGSize, safeAreaTop _: CGFloat) -> ResolvedGeometry? {
        if let topCutout = TopCutoutCatalog.current {
            return ResolvedGeometry(
                topCutout: topCutout,
                source: "Device Table Match",
                modelIdentifier: TopCutoutDemoProbe.currentModelIdentifier()
            )
        }

        return nil
    }

    private func copyDebugReport(_ report: TopCutoutCatalogProbeReport) {
        let payload = report.prettyJSONString
        UIPasteboard.general.string = payload
        print("[TopCutoutDemo] Copied debug report:")
        print(payload)
        copyFeedback = "Copied"

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            copyFeedback = "Copy Debug JSON"
        }
    }

    private func logDebugReportIfNeeded(_ report: TopCutoutCatalogProbeReport) {
        guard report.logKey != lastLoggedReportKey else {
            return
        }

        lastLoggedReportKey = report.logKey
        print("[TopCutoutDemo] Debug report:")
        print(report.prettyJSONString)
        persistDebugReport(report)
    }

    private func persistDebugReport(_ report: TopCutoutCatalogProbeReport) {
        let fileManager = FileManager.default

        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[TopCutoutDemo] Could not resolve documents directory for debug report")
            return
        }

        let reportURL = documentsURL.appendingPathComponent("TopCutoutProbeReport.json")

        do {
            if !fileManager.fileExists(atPath: documentsURL.path) {
                try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            }

            try report.prettyJSONString.write(to: reportURL, atomically: true, encoding: .utf8)
            print("[TopCutoutDemo] Persisted debug report to: \(reportURL.path)")
        } catch {
            print("[TopCutoutDemo] Failed to persist debug report: \(error)")
        }
    }
}

private struct ResolvedGeometry {
    let topCutout: TopCutoutCatalog.TopCutoutInfo
    let source: String
    let modelIdentifier: String
}

private struct TopCutoutCatalogProbeReport: Encodable {
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

private struct ProbeRect: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = TopCutoutCatalogProbeReport.probeValue(rect.origin.x)
        y = TopCutoutCatalogProbeReport.probeValue(rect.origin.y)
        width = TopCutoutCatalogProbeReport.probeValue(rect.width)
        height = TopCutoutCatalogProbeReport.probeValue(rect.height)
    }

    init?(_ value: Any?) {
        if let rect = value as? CGRect {
            self.init(rect)
            return
        }

        if let boxed = value as? NSValue {
            self.init(boxed.cgRectValue)
            return
        }

        return nil
    }
}

private struct ProbeDisplayInfoProvider: Encodable {
    let providerClass: String
    let providerDescription: String
    let artworkSubtype: String?
    let safeAreaInsetsPortrait: ProbeInsets?
    let safeAreaInsetsLandscapeLeft: ProbeInsets?
    let safeAreaInsetsLandscapeRight: ProbeInsets?
    let safeAreaInsetsPortraitUpsideDown: ProbeInsets?
    let peripheryInsets: ProbeInsets?
    let systemMinimumMargin: Double?
    let homeAffordanceOverlayAllowance: Double?
    let exclusionRect: ProbeRect?

    init(_ provider: NSObject) {
        providerClass = String(describing: type(of: provider))
        providerDescription = String(describing: provider)
        artworkSubtype = ProbeDisplayInfoProvider.stringValue(provider.value(forKey: "artworkSubtype"))
        safeAreaInsetsPortrait = ProbeInsets(provider.value(forKey: "safeAreaInsetsPortrait"))
        safeAreaInsetsLandscapeLeft = ProbeInsets(provider.value(forKey: "safeAreaInsetsLandscapeLeft"))
        safeAreaInsetsLandscapeRight = ProbeInsets(provider.value(forKey: "safeAreaInsetsLandscapeRight"))
        safeAreaInsetsPortraitUpsideDown = ProbeInsets(provider.value(forKey: "safeAreaInsetsPortraitUpsideDown"))
        peripheryInsets = ProbeInsets(provider.value(forKey: "peripheryInsets"))
        systemMinimumMargin = ProbeDisplayInfoProvider.doubleValue(provider.value(forKey: "systemMinimumMargin"))
        homeAffordanceOverlayAllowance = ProbeDisplayInfoProvider.doubleValue(
            provider.value(forKey: "homeAffordanceOverlayAllowance")
        )

        if let exclusionArea = provider.value(forKey: "exclusionArea") as? NSObject {
            exclusionRect = ProbeRect(exclusionArea.value(forKey: "rect"))
        } else {
            exclusionRect = nil
        }
    }

    static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let cgFloat = value as? CGFloat {
            return Double(cgFloat)
        }

        return nil
    }

    static func stringValue(_ value: Any?) -> String? {
        value.map { String(describing: $0) }
    }
}

private struct ProbeInsets: Encodable {
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

private struct ProbeSize: Encodable {
    let width: Double
    let height: Double

    init(size: CGSize) {
        width = TopCutoutCatalogProbeReport.probeValue(size.width)
        height = TopCutoutCatalogProbeReport.probeValue(size.height)
    }
}

private struct ProbeGeometry: Encodable {
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

private enum TopCutoutCatalogProbe {
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

private enum TopCutoutDemoProbe {
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

private struct HeaderBlock: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("TopCutout Demo")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .textCase(.uppercase)

            Text("Real Cutout Placement")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("The glow is drawn against the actual top hardware area using the package top-feature data and a full-screen, safe-area-ignoring overlay.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.68))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
    }
}

private struct InfoPanel: View {
    let resolved: ResolvedGeometry

    var body: some View {
        let topCutout = resolved.topCutout

        VStack(alignment: .leading, spacing: 14) {
            Text(title(for: topCutout.kind))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("The overlay position and size come from `TopCutoutCatalog.current`, which resolves from the generated device table.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.74))

            MetricRow(label: "Source", value: resolved.source)
            MetricRow(label: "Model", value: resolved.modelIdentifier)
            MetricRow(
                label: "Geometry",
                value: geometryLabel(for: topCutout)
            )
            MetricRow(
                label: "Top Inset",
                value: topInsetLabel(for: topCutout)
            )
            MetricRow(label: "Kind", value: kindLabel(topCutout.kind))
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

    private func title(for kind: TopCutoutCatalog.TopCutoutKind) -> String {
        switch kind {
        case .dynamicIsland:
            return "Detected Dynamic Island"
        case .notch:
            return "Detected Notch"
        case .none:
            return "Detected Top Feature"
        }
    }

    private func kindLabel(_ kind: TopCutoutCatalog.TopCutoutKind) -> String {
        switch kind {
        case .dynamicIsland:
            return "dynamicIsland"
        case .notch:
            return "notch"
        case .none:
            return "none"
        }
    }

    private func geometryLabel(for topCutout: TopCutoutCatalog.TopCutoutInfo) -> String {
        guard let size = topCutout.size else {
            return "Unavailable"
        }

        return "\(Int(size.width)) x \(Int(size.height)) pt"
    }

    private func topInsetLabel(for topCutout: TopCutoutCatalog.TopCutoutInfo) -> String {
        guard let paddingTop = topCutout.paddingTop else {
            return "Unavailable"
        }

        return "\(Int(paddingTop)) pt"
    }
}

private struct DebugProbePanel: View {
    let report: TopCutoutCatalogProbeReport
    let copyFeedback: String
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Simulator Probe")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Reads `UIScreen._exclusionArea.rect`, infers a cutout geometry, and copies a JSON payload for inspection.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer(minLength: 12)

                Button(action: onCopy) {
                    Text(copyFeedback)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(red: 1, green: 0.45, blue: 0.38))
                        )
                }
                .buttonStyle(.plain)
            }

            MetricRow(label: "Device", value: report.deviceName)
            MetricRow(label: "Model", value: report.modelIdentifier)
            MetricRow(
                label: "Screen",
                value: "\(formatted(report.screenSize.width)) x \(formatted(report.screenSize.height)) pt"
            )
            MetricRow(label: "Safe Area Top", value: "\(formatted(report.safeAreaTop)) pt")
            MetricRow(label: "Exclusion Rect", value: report.exclusionSummary)
            MetricRow(label: "Inferred Geometry", value: report.inferredGeometrySummary)

            if let resolvedSource = report.resolvedSource {
                MetricRow(label: "Resolved Source", value: resolvedSource)
            }

            if let matchesResolvedGeometry = report.matchesResolvedGeometry {
                MetricRow(
                    label: "Matches Resolved",
                    value: matchesResolvedGeometry ? "yes" : "no"
                )
            }
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

    private func formatted(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.000_1 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
    }
}

private extension TopCutoutCatalogProbeReport {
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

private struct UnresolvedPanel: View {
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

private struct DebugExclusionOverlay: View {
    let rect: ProbeRect

    var body: some View {
        Rectangle()
            .stroke(
                Color(red: 0.42, green: 0.93, blue: 1),
                style: StrokeStyle(lineWidth: 2, dash: [7, 4])
            )
            .frame(width: CGFloat(rect.width), height: CGFloat(rect.height))
            .position(
                x: CGFloat(rect.x + (rect.width * 0.5)),
                y: CGFloat(rect.y + (rect.height * 0.5))
            )
    }
}

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.52))

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.38))
        }
    }
}

private struct LiveCutoutOverlay: View {
    let topCutout: TopCutoutCatalog.TopCutoutInfo
    let isGlowing: Bool

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let occupiedBand = topCutout.occupiedTopBand(in: bounds)
            let buttonCenters = topCutout.recommendedButtonCenters(
                in: bounds,
                buttonSize: CGSize(width: 18, height: 18),
                sidePadding: 16
            )

            if let occupiedBand {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: occupiedBand.height + 44)
                    .mask(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white,
                                        .white.opacity(0.7),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )

                    if let buttonCenters {
                        EarStatusDot()
                            .position(x: buttonCenters.leading.x, y: buttonCenters.leading.y)

                        EarStatusDot()
                            .position(x: buttonCenters.trailing.x, y: buttonCenters.trailing.y)
                    }

                    CutoutGlow(
                        topCutout: topCutout,
                        isGlowing: isGlowing
                    )
                }
                .ignoresSafeArea()
            }
        }
    }
}

private struct EarStatusDot: View {
    var body: some View {
        Circle()
            .fill(Color(red: 1, green: 0.34, blue: 0.27))
            .frame(width: 10, height: 10)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: Color(red: 1, green: 0.2, blue: 0.16).opacity(0.55), radius: 8)
    }
}

private struct CutoutGlow: View {
    let topCutout: TopCutoutCatalog.TopCutoutInfo
    let isGlowing: Bool

    private let glowColor = Color(red: 1, green: 0.19, blue: 0.18)

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            if let cutout = topCutout.rect(in: bounds) {
                ZStack {
                    if topCutout.kind == .dynamicIsland {
                        Capsule()
                            .fill(glowColor.opacity(isGlowing ? 0.58 : 0.34))
                            .frame(
                                width: cutout.width + (isGlowing ? 36 : 22),
                                height: cutout.height + (isGlowing ? 24 : 14)
                            )
                            .blur(radius: isGlowing ? 24 : 14)
                            .position(x: cutout.midX, y: cutout.midY)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.black,
                                        Color(red: 0.08, green: 0.03, blue: 0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: cutout.width, height: cutout.height)
                            .overlay {
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.16),
                                                glowColor.opacity(0.65)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                            .position(x: cutout.midX, y: cutout.midY)
                    } else {
                        TopNotchShape()
                            .fill(glowColor.opacity(isGlowing ? 0.42 : 0.25))
                            .frame(
                                width: cutout.width + (isGlowing ? 40 : 26),
                                height: cutout.height + (isGlowing ? 22 : 14)
                            )
                            .blur(radius: isGlowing ? 26 : 16)
                            .position(x: cutout.midX, y: cutout.midY + 4)

                        TopNotchShape()
                            .stroke(glowColor.opacity(isGlowing ? 0.88 : 0.45), lineWidth: 1.5)
                            .frame(width: cutout.width + 8, height: cutout.height + 4)
                            .blur(radius: isGlowing ? 2.6 : 1.6)
                            .position(x: cutout.midX, y: cutout.midY + 1)

                        TopNotchShape()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.black,
                                        Color(red: 0.08, green: 0.03, blue: 0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: cutout.width, height: cutout.height)
                            .overlay {
                                TopNotchShape()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.14),
                                                glowColor.opacity(0.45)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                            .position(x: cutout.midX, y: cutout.midY)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct DemoBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.01, blue: 0.02),
                    Color(red: 0.12, green: 0.01, blue: 0.05),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.red.opacity(0.35))
                .frame(width: 260, height: 260)
                .blur(radius: 100)
                .offset(x: 120, y: -250)

            Circle()
                .fill(Color(red: 1, green: 0.35, blue: 0.16).opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 110)
                .offset(x: -140, y: 180)
        }
    }
}

private struct TopNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let shoulder = width * 0.185
        let neck = width * 0.30
        let base = width * 0.42
        let shoulderDrop = height * 0.24
        let neckDrop = height * 0.62

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: shoulder, y: 0))
        path.addCurve(
            to: CGPoint(x: neck, y: neckDrop),
            control1: CGPoint(x: shoulder + width * 0.04, y: 0),
            control2: CGPoint(x: neck - width * 0.05, y: shoulderDrop)
        )
        path.addCurve(
            to: CGPoint(x: base, y: height),
            control1: CGPoint(x: neck + width * 0.03, y: height * 0.90),
            control2: CGPoint(x: base - width * 0.04, y: height)
        )
        path.addLine(to: CGPoint(x: width - base, y: height))
        path.addCurve(
            to: CGPoint(x: width - neck, y: neckDrop),
            control1: CGPoint(x: width - base + width * 0.04, y: height),
            control2: CGPoint(x: width - neck - width * 0.03, y: height * 0.90)
        )
        path.addCurve(
            to: CGPoint(x: width - shoulder, y: 0),
            control1: CGPoint(x: width - neck + width * 0.05, y: shoulderDrop),
            control2: CGPoint(x: width - shoulder - width * 0.04, y: 0)
        )
        path.addLine(to: CGPoint(x: width, y: 0))
        path.closeSubpath()
        return path
    }
}
