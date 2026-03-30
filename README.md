# TopCutout

`TopCutout` is a small iOS Swift package for retrieving a device's top cutout geometry.

It gives you the size and top inset for the visible notch or Dynamic Island so you can align custom UI around the device's top hardware area.

## What It Provides

- The current device's top cutout style
- The cutout width and height in points
- The distance from the top edge to the cutout
- Helper geometry for the occupied top band and the free space on each side

## Main API

Use `IPhoneTopCutoutCatalog` to fetch geometry:

```swift
import TopCutout

if let geometry = IPhoneTopCutoutCatalog.current {
    print(geometry.style)      // .wideNotch, .narrowNotch, or .dynamicIsland
    print(geometry.size)       // CGSize for the top cutout
    print(geometry.topInset)   // Distance from the top edge
}
```

You can also query a specific model identifier:

```swift
import TopCutout

let geometry = IPhoneTopCutoutCatalog.geometry(for: "iPhone15,2")
```

For unknown future devices, there is also a heuristic fallback based on screen size and safe area:

```swift
import TopCutout
import UIKit

let fallback = IPhoneTopCutoutCatalog.heuristicGeometry(
    screenSize: UIScreen.main.bounds.size,
    safeAreaTop: view.safeAreaInsets.top
)
```

## Use Cases

- Positioning controls to the left and right of the notch
- Laying out custom status bar overlays
- Building camera or preview UI that avoids the top hardware cutout
- Adapting UI between notch devices and Dynamic Island devices

## Platform

- iOS 15+
