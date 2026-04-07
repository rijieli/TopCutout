//
//  ContentView.swift
//  TopCutoutDemo
//
//  Created by Roger on 2026/3/30.
//

import SwiftUI
import TopCutout
import UIKit

private let showSimulatorProbeSection = true

struct ContentView: View {
    @State private var copyFeedback = "Copy Debug JSON"
    @State private var lastLoggedReportKey: String?
    @State private var isShowingSimulatorProbeSheet = false

    var body: some View {
        let screenInfo = TopCutoutCatalog.screen
        let modelIdentifier = TopCutoutDemoProbe.currentModelIdentifier()
        let debugReport = debugProbeReport(for: screenInfo)

        ZStack(alignment: .top) {
            BlueprintBackdrop()

            if let screenInfo {
                BlueprintOverlay(
                    screenInfo: screenInfo,
                    modelIdentifier: modelIdentifier
                )
                    .allowsHitTesting(false)
            }

            if let exclusionRect = debugReport?.exclusionRect {
                DebugExclusionOverlay(rect: exclusionRect)
                    .allowsHitTesting(false)
                }

            VStack(spacing: 22) {
                Spacer()

                HeaderBlock(
                    showsDebugButton: showSimulatorProbeSection,
                    onShowDebug: { isShowingSimulatorProbeSheet = true }
                )

                if screenInfo == nil {
                    UnresolvedPanel()
                }

            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .multilineTextAlignment(.center)
        }
        .ignoresSafeArea()
        .task(id: debugReport?.logKey) {
            if let debugReport {
                logDebugReportIfNeeded(debugReport)
            }
        }
        .sheet(isPresented: $isShowingSimulatorProbeSheet) {
            if let debugReport {
                if #available(iOS 16.0, *) {
                    DebugProbePanel(
                        report: debugReport,
                        copyFeedback: copyFeedback,
                        onCopy: { copyDebugReport(debugReport) }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                } else {
                    DebugProbePanel(
                        report: debugReport,
                        copyFeedback: copyFeedback,
                        onCopy: { copyDebugReport(debugReport) }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var currentSafeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }

    private func debugProbeReport(for screenInfo: TopCutoutCatalog.ScreenInfo?) -> TopCutoutCatalogProbeReport? {
        guard showSimulatorProbeSection else {
            return nil
        }

        let screenSize = screenInfo?.points ?? UIScreen.main.bounds.size
        return TopCutoutCatalogProbeReport.make(
            screenSize: screenSize,
            safeAreaTop: currentSafeAreaTop,
            screenInfo: screenInfo
        )
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

struct ProbeRect: Encodable {
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

struct ProbeDisplayInfoProvider: Encodable {
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

private struct HeaderBlock: View {
    let showsDebugButton: Bool
    let onShowDebug: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("TopCutout Library")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("A technical layout driven by the generated device table, showing the display edge, sensor housing, and the real corner radius geometry.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.72, green: 0.9, blue: 1).opacity(0.82))
                .multilineTextAlignment(.center)

            if showsDebugButton {
                Button(action: onShowDebug) {
                    Text("Show Debug Modal")
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
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 10)
    }
}

private struct BlueprintOverlay: View {
    let screenInfo: TopCutoutCatalog.ScreenInfo
    let modelIdentifier: String

    private let accent = Color(red: 0.57, green: 0.9, blue: 1)
    private let labelHeight: CGFloat = 56
    private let labelGap: CGFloat = 40
    private let cornerLabelWidth: CGFloat = 132
    private let cornerLabelTrailingInset: CGFloat = 40
    private let cornerLabelTopGap: CGFloat = 20
    private let notchOverlayLabelGap: CGFloat = 20

    private var topCutout: TopCutoutCatalog.TopCutoutInfo {
        screenInfo.topCutout
    }

    var body: some View {
        let bounds = screenInfo.bounds
        let cornerRadius = screenInfo.fittedCornerRadius(in: bounds)
        let cutout = topCutout.rect(in: bounds)
        let displayEdgeTarget = CGPoint(
            x: 0,
            y: bounds.midY
        )
        let topRightCornerCenter = CGPoint(
            x: bounds.maxX - cornerRadius,
            y: bounds.minY + cornerRadius
        )
        let cornerTarget = CGPoint(
            x: topRightCornerCenter.x + cornerRadius * 0.7071,
            y: topRightCornerCenter.y - cornerRadius * 0.7071
        )
        let displayLabelPosition = CGPoint(
            x: bounds.midX,
            y: bounds.midY
        )
        let sensorLabelPosition: CGPoint? = {
            guard cutout != nil else {
                return nil
            }

            return CGPoint(
                x: displayLabelPosition.x,
                y: displayLabelPosition.y - labelHeight - labelGap
            )
        }()
        let cornerLabelPosition = CGPoint(
            x: bounds.maxX - cornerLabelTrailingInset - (cornerLabelWidth * 0.5),
            y: (cutout?.maxY ?? 0) + cornerLabelTopGap + (labelHeight * 0.5)
        )
        let notchOverlay = notchOverlay(
            in: bounds,
            sensorLabelPosition: sensorLabelPosition
        )

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(accent.opacity(0.82), lineWidth: 2)
                .frame(width: bounds.width, height: bounds.height)

            if let notchOverlay {
                Color.clear
                    .frame(width: bounds.width, height: bounds.height)
                    .overlay(alignment: .topLeading) {
                        BlueprintNotchOverlay(path: notchOverlay.path, accent: accent)
                            .frame(
                                width: notchOverlay.frame.width,
                                height: notchOverlay.frame.height,
                                alignment: .topLeading
                            )
                            .offset(x: notchOverlay.frame.minX, y: notchOverlay.frame.minY)
                    }
            }

            BlueprintArrow(
                from: CGPoint(x: displayLabelPosition.x - 72, y: displayLabelPosition.y),
                to: displayEdgeTarget,
                color: accent
            )

            BlueprintLabel(
                title: "Display Edge",
                value: "\(Int(screenInfo.points.width)) x \(Int(screenInfo.points.height)) pt",
                detail: "\(format(screenInfo.scale))x scale • \(screenInfo.pixelsLabel)",
                accent: accent
            )
            .position(x: displayLabelPosition.x, y: displayLabelPosition.y)

            if let cutout, let sensorLabelPosition {
                BlueprintArrow(
                    from: CGPoint(
                        x: sensorLabelPosition.x,
                        y: sensorLabelPosition.y + (labelHeight * 0.5) - 10
                    ),
                    to: CGPoint(x: cutout.midX, y: cutout.midY),
                    color: accent
                )

                BlueprintLabel(
                    title: "Sensor Housing",
                    value: "\(format(topCutout.size?.width ?? 0)) x \(format(topCutout.size?.height ?? 0)) pt",
                    detail: sensorHousingDetail,
                    accent: accent
                )
                .position(x: sensorLabelPosition.x, y: sensorLabelPosition.y)
            }

            if cornerRadius > 0 {
                BlueprintArrow(
                    from: CGPoint(
                        x: cornerLabelPosition.x - 28,
                        y: cornerLabelPosition.y - 12
                    ),
                    to: cornerTarget,
                    color: accent
                )

                BlueprintLabel(
                    title: "Corner Radius",
                    value: "\(format(screenInfo.cornerRadiusPoints ?? 0)) pt",
                    detail: nil,
                    accent: accent
                )
                .position(x: cornerLabelPosition.x, y: cornerLabelPosition.y)
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .ignoresSafeArea()
    }

    private func format(_ value: CGFloat) -> String {
        if abs(value.rounded() - value) < 0.000_1 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
    }

    private func notchOverlay(
        in bounds: CGRect,
        sensorLabelPosition: CGPoint?
    ) -> (path: Path, frame: CGRect)? {
        guard topCutout.kind == .notch,
              let cutout = topCutout.rect(in: bounds),
              let sensorLabelPosition,
              let device = TopCutoutCatalog.Device(rawValue: modelIdentifier),
              let sensorHousingPath = device.sensorHousingPath else {
            return nil
        }

        let sourceBounds = sensorHousingPath.boundingRect
        guard sourceBounds.width > 0, sourceBounds.height > 0 else {
            return nil
        }

        let normalized = sensorHousingPath.applying(
            CGAffineTransform(translationX: -sourceBounds.minX, y: -sourceBounds.minY)
        )
        let scaled = normalized.applying(
            CGAffineTransform(
                scaleX: cutout.width / sourceBounds.width,
                y: cutout.height / sourceBounds.height
            )
        )
        let flipped = scaled.applying(
            CGAffineTransform(translationX: 0, y: cutout.height)
                .scaledBy(x: 1, y: -1)
        )

        let overlayOrigin = CGPoint(
            x: sensorLabelPosition.x - (cutout.width * 0.5),
            y: sensorLabelPosition.y - (labelHeight * 0.5) - notchOverlayLabelGap - cutout.height
        )

        return (
            path: flipped,
            frame: CGRect(origin: overlayOrigin, size: CGSize(width: cutout.width, height: cutout.height))
        )
    }

    private var sensorHousingDetail: String {
        if let paddingTop = topCutout.paddingTop, paddingTop > 0.000_1 {
            return "Top gap \(format(paddingTop)) pt"
        }

        switch topCutout.kind {
        case .dynamicIsland:
            return "Dynamic Island"
        case .notch:
            return "Top Notch"
        case .none:
            return "No Cutout"
        }
    }
}

private struct BlueprintNotchOverlay: View {
    let path: Path
    let accent: Color

    var body: some View {
        let shape = BlueprintPathShape(path: path)

        ZStack {
            BlueprintHatchPattern(spacing: 8)
                .stroke(accent.opacity(0.34), lineWidth: 1)
                .clipShape(shape)

            shape
                .stroke(accent.opacity(0.72), lineWidth: 1.2)
        }
    }
}

private struct BlueprintPathShape: Shape {
    let path: Path

    func path(in _: CGRect) -> Path {
        path
    }
}

private struct BlueprintLabel: View {
    let title: String
    let value: String
    let detail: String?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(accent.opacity(0.74))

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.72))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.03, green: 0.15, blue: 0.24).opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                }
        )
    }
}

private struct BlueprintArrow: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: from)
                path.addLine(to: to)

                let angle = atan2(to.y - from.y, to.x - from.x)
                let arrowLength: CGFloat = 10
                let arrowAngle: CGFloat = .pi / 7

                path.move(to: to)
                path.addLine(
                    to: CGPoint(
                        x: to.x - cos(angle - arrowAngle) * arrowLength,
                        y: to.y - sin(angle - arrowAngle) * arrowLength
                    )
                )
                path.move(to: to)
                path.addLine(
                    to: CGPoint(
                        x: to.x - cos(angle + arrowAngle) * arrowLength,
                        y: to.y - sin(angle + arrowAngle) * arrowLength
                    )
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))

            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .position(x: to.x, y: to.y)
        }
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
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(22)
    }

    private func formatted(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.000_1 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
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

private struct BlueprintBackdrop: View {
    private let accent = Color(red: 0.57, green: 0.9, blue: 1)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.08, blue: 0.13),
                    Color(red: 0.03, green: 0.12, blue: 0.2),
                    Color(red: 0.01, green: 0.04, blue: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            BlueprintGrid(spacing: 24, color: accent.opacity(0.08))
                .ignoresSafeArea()

            BlueprintGrid(spacing: 120, color: accent.opacity(0.16))
                .ignoresSafeArea()

            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: 120, y: -280)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 110)
                .offset(x: -150, y: 220)
        }
    }
}

private struct BlueprintGrid: View {
    let spacing: CGFloat
    let color: Color

    var body: some View {
        BlueprintGridShape(spacing: spacing)
            .stroke(color, lineWidth: 0.8)
    }
}

private struct BlueprintGridShape: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += spacing
        }

        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += spacing
        }

        return path
    }
}

private struct BlueprintHatchPattern: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        var startX = -rect.height
        while startX <= rect.width + rect.height {
            path.move(to: CGPoint(x: startX, y: rect.height))
            path.addLine(to: CGPoint(x: startX + rect.height, y: 0))
            startX += spacing
        }

        return path
    }
}

extension TopCutoutCatalog.ScreenInfo {
    var resolutionSourceLabel: String {
        isResolvedByScreenSize ? "Nearest Size Match" : "Device Table Match"
    }

    fileprivate var bounds: CGRect {
        CGRect(origin: .zero, size: points)
    }

    fileprivate func fittedScale(in bounds: CGRect) -> CGFloat {
        let sourceMin = min(points.width, points.height)
        let sourceMax = max(points.width, points.height)
        let boundsMin = min(bounds.width, bounds.height)
        let boundsMax = max(bounds.width, bounds.height)

        guard sourceMin > 0, sourceMax > 0 else {
            return 1
        }

        return min(boundsMin / sourceMin, boundsMax / sourceMax)
    }

    fileprivate func fittedCornerRadius(in bounds: CGRect) -> CGFloat {
        max(0, (cornerRadiusPoints ?? 0) * fittedScale(in: bounds))
    }

    fileprivate var pixelsLabel: String {
        "\(Int(pixels.width)) x \(Int(pixels.height)) px"
    }
}
