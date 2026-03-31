# TopCutout

`TopCutout` is a small iOS Swift package for retrieving a device's top cutout geometry.

It gives you the size and top inset for the visible notch or Dynamic Island so you can align custom UI around the device's top hardware area.

## What It Provides

- The current device's top cutout style
- The cutout width and height in points
- The distance from the top edge to the cutout
- Helper geometry for the occupied top band and the free space on each side

## Main API

Use `TopCutoutCatalog` to fetch the current screen and top feature:

```swift
import TopCutout

if let topFeature = TopCutoutCatalog.current {
    print(topFeature.kind)         // .notch or .dynamicIsland
    print(topFeature.size)         // CGSize for the top cutout
    print(topFeature.paddingTop)   // Distance from the top edge
}

if let screen = TopCutoutCatalog.screen {
    print(screen.points)           // logical screen size
    print(screen.pixels)           // pixel size
    print(screen.topFeature.kind)  // same top-feature data via screen
}
```

The geometry table is generated from simulator device data and runtime probes for Dynamic Island devices.

## Use Cases

- Positioning controls to the left and right of the notch
- Laying out custom status bar overlays
- Building camera or preview UI that avoids the top hardware cutout
- Adapting UI between notch devices and Dynamic Island devices

## Platform

- iOS 15+
