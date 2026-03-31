# TopCutout

`TopCutout` is a small iOS Swift package that exposes top cutout geometry for iPhone screens, including classic notches and Dynamic Island devices.

It is useful when you need more than safe-area insets alone. Instead of only knowing how far content should stay away from the top edge, you can retrieve the cutout kind, exact cutout size, top padding, and helper geometry for the free space on each side.

## Why This Exists

Safe-area insets tell you the protected region, but they do not tell you the shape or width of the visible hardware cutout. That matters for interfaces such as:

- camera and capture overlays
- custom status-bar treatments
- controls that sit to the left and right of the notch
- immersive media UIs that need precise top-edge alignment
- Dynamic Island-aware layouts and prototypes

## Features

- Runtime lookup for the current device using the model identifier
- Generated catalog of iPhone screen metadata and top cutout geometry
- Distinguishes between `.none`, `.notch`, and `.dynamicIsland`
- Helper APIs for the cutout rect, occupied top band, and left/right "ear" regions
- Optional SwiftUI `Path` data for supported sensor housing outlines
- Included demo app and catalog-generation scripts

## Requirements

- iOS 15+
- Swift 5.8+
- Xcode with Swift Package Manager support

## Installation

Add the package in Xcode with `File > Add Package Dependencies...`, or declare it in `Package.swift`:

```swift
dependencies: [
    .package(url: "<repository-url>", branch: "main")
]
```

Then add the product to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "TopCutout", package: "TopCutout")
    ]
)
```

## Quick Start

```swift
import SwiftUI
import TopCutout

struct CameraHeader: View {
    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let topCutout = TopCutoutCatalog.current

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                if let cutoutRect = topCutout?.rect(in: bounds) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: cutoutRect.width, height: cutoutRect.height)
                        .position(x: cutoutRect.midX, y: cutoutRect.midY)
                }

                if let centers = topCutout?.recommendedButtonCenters(
                    in: bounds,
                    buttonSize: CGSize(width: 32, height: 32)
                ) {
                    Image(systemName: "bolt.fill")
                        .position(centers.leading)

                    Image(systemName: "gearshape.fill")
                        .position(centers.trailing)
                }
            }
        }
    }
}
```

For simple inspection:

```swift
import TopCutout

if let topCutout = TopCutoutCatalog.current {
    print(topCutout.kind)       // .none, .notch, or .dynamicIsland
    print(topCutout.size)       // CGSize?
    print(topCutout.paddingTop) // CGFloat?
}

if let screen = TopCutoutCatalog.screen {
    print(screen.points)                // logical screen size
    print(screen.pixels)                // native pixel size
    print(screen.scale)                 // display scale
    print(screen.topCutout.kind)        // same cutout data via screen info
    print(screen.cornerRadiusPoints)    // optional corner radius
}
```

## API Overview

### `TopCutoutCatalog`

Primary entry point for runtime lookup.

- `TopCutoutCatalog.current -> TopCutoutInfo?`
- `TopCutoutCatalog.screen -> ScreenInfo?`

Both values are `nil` when the current model identifier is not present in the generated catalog.

### `TopCutoutInfo`

Represents the top hardware cutout for a screen.

- `kind`
- `geometryAvailable`
- `curveAvailable`
- `size`
- `paddingTop`
- `rect(in:)`
- `occupiedTopBand(in:)`
- `leadingEarRect(in:)`
- `trailingEarRect(in:)`
- `recommendedButtonCenters(in:buttonSize:sidePadding:)`

### `ScreenInfo`

Screen metadata paired with the cutout data.

- `points`
- `pixels`
- `scale`
- `dpi`
- `cornerRadiusPoints`
- `topCutout`

### `TopCutoutCatalog.Device`

Generated catalog of known iPhone model identifiers with:

- `displayName`
- `screen`
- `sensorHousingPath`

The current generated catalog includes 42 iPhone identifiers.

## How The Data Is Built

This package is driven by generated source files in [`Sources/TopCutout`](./Sources/TopCutout).

The repository includes tooling that:

1. reads Simulator device bundles from CoreSimulator
2. extracts screen and sensor housing assets
3. probes Dynamic Island simulator devices using the demo app
4. writes generated Swift sources consumed by the package

Relevant scripts:

- [`inspect_simulator_topcutouts.py`](./inspect_simulator_topcutouts.py)
- [`collect_dynamic_island_simulator_info.py`](./collect_dynamic_island_simulator_info.py)

This keeps the runtime API small while letting the catalog be refreshed from newer Simulator data.

## Development

Build the package for iOS Simulator:

```bash
xcodebuild -scheme TopCutout -destination 'generic/platform=iOS Simulator' build
```

Refresh the generated catalog from installed Simulator assets:

```bash
python3 inspect_simulator_topcutouts.py
```

Refresh Dynamic Island probe results with the demo app workflow:

```bash
python3 collect_dynamic_island_simulator_info.py
```

## Demo App

[`TopCutoutDemo`](./TopCutoutDemo) is a lightweight SwiftUI app used both as a visual demo and as part of the probing workflow for Dynamic Island geometry.

Use it to:

- visualize the resolved cutout region
- inspect debug output for the current simulator
- validate spacing assumptions when updating generated data

## Project Layout

- [`Sources/TopCutout`](./Sources/TopCutout): package source and generated catalog files
- [`TopCutoutDemo`](./TopCutoutDemo): example app and probe target
- [`fetch_result`](./fetch_result): copied Simulator assets and generated manifests
- [`simulator_dynamic_island_info.json`](./simulator_dynamic_island_info.json): stored probe results used during generation

## Limitations

- The package currently targets iPhone metadata only.
- Lookup is table-driven, so unknown future model identifiers return `nil`.
- Geometry is derived from Simulator assets and simulator probing, not measured from physical-device capture.
- `sensorHousingPath` is optional and only available where source curve data exists.
- There is no dedicated Swift test target yet; the demo app and generation workflow are the current validation path.

If you use this for pixel-critical production UI, validate the result on the device classes you care about.

## Contributing

Contributions are most useful when they improve one of these areas:

- newly released device support
- corrections to generated geometry
- better demo coverage
- tests and validation tooling
- documentation and examples

When changing generated data, keep the generated Swift files and the source data in sync.

## Status

The package is intentionally focused: one small runtime API, generated device metadata, and tooling to refresh the catalog as Simulator data changes.
