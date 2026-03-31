import UIKit

public enum IPhoneTopCutoutCatalog {
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
        guard let device = IPhoneDevice(rawValue: modelIdentifier) else {
            return nil
        }

        return geometry(for: device.topFeature)
    }

    private static func geometry(for topFeature: IPhoneTopFeatureInfo) -> TopCutoutGeometry? {
        guard let size = topFeature.size, let paddingTop = topFeature.paddingTop else {
            return nil
        }

        let style: TopCutoutStyle
        switch topFeature.kind {
        case .none:
            return nil
        case .dynamicIsland:
            style = .dynamicIsland
        case .notch:
            style = size.width >= 200 ? .wideNotch : .narrowNotch
        }

        return TopCutoutGeometry(
            style: style,
            size: size,
            topInset: paddingTop
        )
    }
}
