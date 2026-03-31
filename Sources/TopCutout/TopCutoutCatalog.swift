import UIKit

public enum TopCutoutCatalog {
    public static let screen: ScreenInfo? = {
        screenInfo(for: currentModelIdentifier())
    }()

    public static let current: TopCutoutInfo? = {
        screen?.topCutout
    }()

    private static func currentModelIdentifier() -> String {
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

    private static func screenInfo(for modelIdentifier: String) -> ScreenInfo? {
        Device(rawValue: modelIdentifier)?.screen
    }
}
