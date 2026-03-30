//
//  ContentView.swift
//  TopCutoutDemo
//
//  Created by Roger on 2026/3/30.
//

import SwiftUI
import TopCutout

struct ContentView: View {
    @State private var isGlowing = false

    var body: some View {
        GeometryReader { proxy in
            let resolved = resolvedGeometry(
                screenSize: proxy.size,
                safeAreaTop: proxy.safeAreaInsets.top
            )
            let cutoutBottom = resolved.map { $0.geometry.topInset + $0.geometry.size.height } ?? proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                DemoBackdrop()

                if let resolved {
                    LiveCutoutOverlay(
                        geometry: resolved.geometry,
                        isGlowing: isGlowing
                    )
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
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }

    private func resolvedGeometry(screenSize: CGSize, safeAreaTop: CGFloat) -> ResolvedGeometry? {
        if let geometry = IPhoneTopCutoutCatalog.current {
            return ResolvedGeometry(
                geometry: geometry,
                source: "Catalog Match",
                modelIdentifier: IPhoneTopCutoutCatalog.currentModelIdentifier()
            )
        }

        if let geometry = IPhoneTopCutoutCatalog.heuristicGeometry(
            screenSize: screenSize,
            safeAreaTop: safeAreaTop
        ) {
            return ResolvedGeometry(
                geometry: geometry,
                source: "Heuristic Fallback",
                modelIdentifier: IPhoneTopCutoutCatalog.currentModelIdentifier()
            )
        }

        return nil
    }
}

private struct ResolvedGeometry {
    let geometry: TopCutoutGeometry
    let source: String
    let modelIdentifier: String
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

            Text("The glow is drawn against the actual top hardware area using the package geometry and a full-screen, safe-area-ignoring overlay.")
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
        VStack(alignment: .leading, spacing: 14) {
            Text(title(for: resolved.geometry.style))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("The overlay position and size come from `IPhoneTopCutoutCatalog.current`, with the package heuristic as fallback.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.74))

            MetricRow(label: "Source", value: resolved.source)
            MetricRow(label: "Model", value: resolved.modelIdentifier)
            MetricRow(
                label: "Geometry",
                value: "\(Int(resolved.geometry.size.width)) x \(Int(resolved.geometry.size.height)) pt"
            )
            MetricRow(
                label: "Top Inset",
                value: "\(Int(resolved.geometry.topInset)) pt"
            )
            MetricRow(label: "Style", value: styleLabel(resolved.geometry.style))
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

    private func title(for style: TopCutoutStyle) -> String {
        switch style {
        case .dynamicIsland:
            return "Detected Dynamic Island"
        case .wideNotch:
            return "Detected Wide Notch"
        case .narrowNotch:
            return "Detected Narrow Notch"
        }
    }

    private func styleLabel(_ style: TopCutoutStyle) -> String {
        switch style {
        case .dynamicIsland:
            return "dynamicIsland"
        case .wideNotch:
            return "wideNotch"
        case .narrowNotch:
            return "narrowNotch"
        }
    }
}

private struct UnresolvedPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No cutout geometry resolved")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("The current device was not matched by the catalog and the heuristic fallback did not return a supported cutout shape.")
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
    let geometry: TopCutoutGeometry
    let isGlowing: Bool

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let occupiedBand = geometry.occupiedTopBand(in: bounds)
            let buttonCenters = geometry.recommendedButtonCenters(
                in: bounds,
                buttonSize: CGSize(width: 18, height: 18),
                sidePadding: 16
            )

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
                    geometry: geometry,
                    isGlowing: isGlowing
                )
            }
            .ignoresSafeArea()
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
    let geometry: TopCutoutGeometry
    let isGlowing: Bool

    private let glowColor = Color(red: 1, green: 0.19, blue: 0.18)

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let cutout = geometry.rect(in: bounds)

            ZStack {
                if geometry.style == .dynamicIsland {
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

