import UIKit

/// Resolves generated screen and top cutout metadata for the current iPhone model.
///
/// `TopCutoutCatalog` is the main runtime entry point for the package. It reads the current
/// model identifier, matches it against the generated device catalog, and exposes the resulting
/// ``ScreenInfo`` and ``TopCutoutInfo`` values.
///
/// On Simulator, lookup prefers `SIMULATOR_MODEL_IDENTIFIER`. On device, lookup uses `uname`.
public enum TopCutoutCatalog {
    /// Screen metadata for the current device.
    ///
    /// This value is resolved once from the current model identifier and returns the generated
    /// catalog entry for that device.
    ///
    /// - Returns: The matched screen metadata, or `nil` when the current model identifier is not
    ///   present in the generated catalog.
    public static let screen: ScreenInfo? = {
        screenInfo(for: currentModelIdentifier())
    }()

    /// Top cutout metadata for the current device.
    ///
    /// This is a convenience accessor for `TopCutoutCatalog.screen?.topCutout`.
    ///
    /// - Returns: The matched top cutout metadata, or `nil` when the current model identifier is
    ///   not present in the generated catalog.
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
