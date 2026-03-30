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
        generatedMap[modelIdentifier]
    }

    /// Optional fallback when you want something for unknown future devices.
    /// This is intentionally conservative.
    public static func heuristicGeometry(
        screenSize: CGSize,
        safeAreaTop: CGFloat
    ) -> TopCutoutGeometry? {
        generatedHeuristicGeometry(screenSize: screenSize, safeAreaTop: safeAreaTop)
    }
}
