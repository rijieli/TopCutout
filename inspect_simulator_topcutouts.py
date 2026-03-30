#!/usr/bin/env python3

"""
Inspect installed or mounted Xcode/CoreSimulator packages and extract device
screen metrics plus any top-cutout assets exposed by *.simdevicetype bundles.

This script is intentionally dependency-free. It uses:
- Python stdlib for plist/PDF/PNG parsing
- macOS `hdiutil` to mount .dmg files
- macOS `sips` to rasterize PDF assets when present

Important limitation:
- Notch-era iPhone simulator bundles include drawable `sensor_bar_class_01/02/03`
  PDFs, so the package exposes a concrete top bar asset.
- Dynamic Island iPhone bundles currently declare Dynamic Island support, but the
  shipped `sensor_bar_class_04/05` PDFs are blank pages. That means the package
  does not expose the exact island silhouette numerically by itself.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MEDIABOX_RE = re.compile(
    rb"/MediaBox\s*\[\s*0\s+0\s+([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)\s*\]"
)
OBJ_STREAM_RE = re.compile(
    rb"(\d+)\s+(\d+)\s+obj\s*<<(.*?)>>\s*stream\r?\n",
    re.S,
)
NUMBER_TOKEN_RE = re.compile(rb"^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$")
PATH_OPERATOR_ARITY = {
    "m": 2,
    "l": 2,
    "c": 6,
    "v": 4,
    "y": 4,
    "h": 0,
    "re": 4,
    "W": 0,
    "W*": 0,
    "n": 0,
    "S": 0,
    "s": 0,
    "f": 0,
    "f*": 0,
    "F": 0,
    "B": 0,
    "B*": 0,
    "b": 0,
    "b*": 0,
}
COMMON_OPERATOR_ARITY = {
    "q": 0,
    "Q": 0,
    "cm": 6,
    "w": 1,
    "J": 1,
    "j": 1,
    "M": 1,
    "i": 1,
    "gs": 1,
    "g": 1,
    "G": 1,
    "rg": 3,
    "RG": 3,
    "k": 4,
    "K": 4,
    "cs": 1,
    "CS": 1,
    "sc": 1,
    "SC": 1,
    "scn": 1,
    "SCN": 1,
}


@dataclass
class MountedDMG:
    mount_point: Path
    image_path: Path


def fail(message: str) -> "Never":
    print(message, file=sys.stderr)
    raise SystemExit(1)


def run_command(args: list[str], *, check: bool = True, capture_output: bool = True) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        args,
        check=check,
        capture_output=capture_output,
    )


def mount_dmg(dmg_path: Path) -> MountedDMG:
    result = run_command(
        ["hdiutil", "attach", "-readonly", "-nobrowse", "-plist", str(dmg_path)]
    )
    payload = plistlib.loads(result.stdout)

    mount_point = None
    for entity in payload.get("system-entities", []):
        value = entity.get("mount-point")
        if value:
            mount_point = Path(value)
            break

    if mount_point is None:
        fail(f"Mounted {dmg_path}, but no mount point was returned by hdiutil.")

    return MountedDMG(mount_point=mount_point, image_path=dmg_path)


def unmount_dmg(mounted: MountedDMG) -> None:
    run_command(["hdiutil", "detach", str(mounted.mount_point)], check=False)


def parse_plist(path: Path) -> dict:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def round_number(value: float) -> float | int:
    rounded = round(value)
    if abs(value - rounded) < 1e-9:
        return int(rounded)
    return round(value, 4)


def parse_pdf_media_box(pdf_path: Path) -> tuple[float, float] | None:
    data = pdf_path.read_bytes()
    match = MEDIABOX_RE.search(data)
    if not match:
        return None
    return float(match.group(1)), float(match.group(2))


def extract_pdf_flate_streams(pdf_path: Path) -> list[bytes]:
    data = pdf_path.read_bytes()
    streams: list[bytes] = []
    for match in OBJ_STREAM_RE.finditer(data):
        header = match.group(3)
        if b"/FlateDecode" not in header:
            continue
        stream_start = match.end()
        stream_end = data.find(b"endstream", stream_start)
        if stream_end == -1:
            continue

        compressed = data[stream_start:stream_end]
        compressed = compressed.rstrip(b"\r\n")
        try:
            streams.append(zlib.decompress(compressed))
        except zlib.error:
            continue

    return streams


def looks_like_pdf_path_stream(stream: bytes) -> bool:
    if not stream:
        return False

    printable = sum(32 <= byte <= 126 or byte in (9, 10, 13) for byte in stream)
    if printable / len(stream) < 0.85:
        return False

    decoded = stream.decode("latin1", "ignore")
    return bool(
        re.search(r"(?<![A-Za-z])[mlcvyhreWnSsFfBb](?:\*?)(?![A-Za-z])", decoded)
    )


def token_is_number(token: bytes) -> bool:
    return bool(NUMBER_TOKEN_RE.match(token))


def parse_pdf_path_commands(stream: bytes) -> list[dict]:
    tokens = stream.split()
    number_stack: list[float] = []
    commands: list[dict] = []

    for token in tokens:
        if token_is_number(token):
            number_stack.append(float(token))
            continue

        operator = token.decode("latin1", "ignore")
        if operator in PATH_OPERATOR_ARITY:
            arity = PATH_OPERATOR_ARITY[operator]
            args = number_stack[-arity:] if arity else []
            if arity:
                if len(number_stack) < arity:
                    number_stack.clear()
                    continue
                del number_stack[-arity:]
            commands.append(
                {
                    "op": operator,
                    "args": [round_number(value) for value in args],
                }
            )
            continue

        if operator in COMMON_OPERATOR_ARITY:
            arity = COMMON_OPERATOR_ARITY[operator]
            if arity and len(number_stack) >= arity:
                del number_stack[-arity:]
            else:
                number_stack.clear()
            continue

        number_stack.clear()

    return commands


def summarize_path_commands(commands: list[dict]) -> dict:
    summary = {
        "command_count": len(commands),
        "subpath_count": 0,
        "has_beziers": False,
        "operators": [],
    }

    if not commands:
        return summary

    operators = [command["op"] for command in commands]
    summary["operators"] = sorted(set(operators))
    summary["has_beziers"] = any(op in {"c", "v", "y"} for op in operators)
    summary["subpath_count"] = sum(1 for op in operators if op in {"m", "re"})
    return summary


def inspect_pdf_vector_paths(pdf_path: Path, *, include_curves: bool) -> dict:
    streams = extract_pdf_flate_streams(pdf_path)
    path_streams = [stream for stream in streams if looks_like_pdf_path_stream(stream)]

    vector_info = {
        "has_vector_paths": False,
        "stream_count": 0,
        "path_summaries": [],
    }

    if not path_streams:
        return vector_info

    vector_info["has_vector_paths"] = True
    vector_info["stream_count"] = len(path_streams)

    for stream in path_streams:
        commands = parse_pdf_path_commands(stream)
        if not commands:
            continue

        path_summary = summarize_path_commands(commands)
        if include_curves:
            path_summary["commands"] = commands
        vector_info["path_summaries"].append(path_summary)

    if not vector_info["path_summaries"]:
        vector_info["has_vector_paths"] = False
        vector_info["stream_count"] = 0

    return vector_info


def rasterize_pdf_to_png(pdf_path: Path, png_path: Path) -> None:
    run_command(
        ["sips", "-s", "format", "png", str(pdf_path), "--out", str(png_path)],
    )


def paeth_predictor(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode_png_alpha_bbox(png_path: Path) -> dict | None:
    data = png_path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"{png_path} is not a PNG file")

    position = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = None
    palette: list[tuple[int, int, int]] | None = None
    trns = b""
    idat_chunks = bytearray()

    while position < len(data):
        length = int.from_bytes(data[position : position + 4], "big")
        position += 4
        chunk_type = data[position : position + 4]
        position += 4
        chunk_data = data[position : position + length]
        position += length
        position += 4  # CRC

        if chunk_type == b"IHDR":
            width = int.from_bytes(chunk_data[0:4], "big")
            height = int.from_bytes(chunk_data[4:8], "big")
            bit_depth = chunk_data[8]
            color_type = chunk_data[9]
        elif chunk_type == b"PLTE":
            palette = [
                (chunk_data[i], chunk_data[i + 1], chunk_data[i + 2])
                for i in range(0, len(chunk_data), 3)
            ]
        elif chunk_type == b"tRNS":
            trns = chunk_data
        elif chunk_type == b"IDAT":
            idat_chunks.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    if width is None or height is None or bit_depth is None or color_type is None:
        raise ValueError(f"{png_path} is missing IHDR metadata")

    if bit_depth != 8:
        raise ValueError(
            f"{png_path} uses unsupported PNG bit depth {bit_depth}; expected 8"
        )

    channels_by_color_type = {
        0: 1,  # grayscale
        2: 3,  # rgb
        3: 1,  # indexed
        4: 2,  # grayscale + alpha
        6: 4,  # rgba
    }
    if color_type not in channels_by_color_type:
        raise ValueError(
            f"{png_path} uses unsupported PNG color type {color_type}"
        )

    channels = channels_by_color_type[color_type]
    bytes_per_pixel = channels
    stride = width * bytes_per_pixel
    raw = zlib.decompress(bytes(idat_chunks))

    min_x = width
    min_y = height
    max_x = -1
    max_y = -1

    previous_row = bytearray(stride)
    offset = 0
    for y in range(height):
        filter_type = raw[offset]
        offset += 1

        row = bytearray(raw[offset : offset + stride])
        offset += stride

        if filter_type == 1:
            for i in range(stride):
                row[i] = (row[i] + (row[i - bytes_per_pixel] if i >= bytes_per_pixel else 0)) & 0xFF
        elif filter_type == 2:
            for i in range(stride):
                row[i] = (row[i] + previous_row[i]) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = row[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
                up = previous_row[i]
                row[i] = (row[i] + ((left + up) >> 1)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                left = row[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
                up = previous_row[i]
                up_left = previous_row[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
                row[i] = (row[i] + paeth_predictor(left, up, up_left)) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"{png_path} uses unsupported PNG filter {filter_type}")

        for x in range(width):
            start = x * bytes_per_pixel

            if color_type == 0:
                gray = row[start]
                alpha = 255
                if len(trns) >= 2 and gray == trns[1]:
                    alpha = 0
            elif color_type == 2:
                red, green, blue = row[start : start + 3]
                alpha = 255
                if len(trns) >= 6:
                    transparent_rgb = (trns[1], trns[3], trns[5])
                    if (red, green, blue) == transparent_rgb:
                        alpha = 0
            elif color_type == 3:
                palette_index = row[start]
                if palette is None:
                    raise ValueError(f"{png_path} indexed PNG is missing a palette")
                alpha = trns[palette_index] if palette_index < len(trns) else 255
            elif color_type == 4:
                alpha = row[start + 1]
            else:  # color_type == 6
                alpha = row[start + 3]

            if alpha > 0:
                if x < min_x:
                    min_x = x
                if y < min_y:
                    min_y = y
                if x > max_x:
                    max_x = x
                if y > max_y:
                    max_y = y

        previous_row = row

    if max_x < 0:
        return None

    return {
        "x": min_x,
        "y": min_y,
        "width": max_x - min_x + 1,
        "height": max_y - min_y + 1,
    }


def find_simdevicetype_roots(source_path: Path) -> list[Path]:
    if source_path.is_dir() and source_path.name.endswith(".simdevicetype"):
        return [source_path]

    candidates = []
    direct_device_types = source_path / "Library/Developer/CoreSimulator/Profiles/DeviceTypes"
    if direct_device_types.is_dir():
        candidates.append(direct_device_types)

    if source_path.name == "DeviceTypes" and source_path.is_dir():
        candidates.append(source_path)

    if candidates:
        roots = []
        for candidate in candidates:
            roots.extend(sorted(candidate.glob("*.simdevicetype")))
        return roots

    if source_path.is_dir():
        return sorted(source_path.rglob("*.simdevicetype"))

    return []


def inspect_pdf_asset(
    pdf_path: Path,
    *,
    asset_name: str,
    include_curves: bool,
    inspect_raster_bounds: bool,
) -> dict:
    page_size = parse_pdf_media_box(pdf_path)
    vector_paths = inspect_pdf_vector_paths(pdf_path, include_curves=include_curves)

    opaque_bounds = None
    status = "pdf_present"
    if inspect_raster_bounds:
        with tempfile.TemporaryDirectory(prefix="sim-topcutout-") as temp_dir:
            png_path = Path(temp_dir) / f"{asset_name}.png"
            rasterize_pdf_to_png(pdf_path, png_path)
            opaque_bounds = decode_png_alpha_bbox(png_path)
        status = "rendered" if opaque_bounds else "blank_pdf"

    asset = {
        "name": asset_name,
        "status": status,
        "pdf_path": str(pdf_path),
        "page_size_points": None,
        "vector_paths": vector_paths,
    }

    if inspect_raster_bounds:
        asset["opaque_bounds_points"] = opaque_bounds

    if page_size:
        asset["page_size_points"] = {
            "width": round_number(page_size[0]),
            "height": round_number(page_size[1]),
        }

    return asset


def inspect_sensor_bar_asset(
    resources_dir: Path,
    sensor_bar_name: str | None,
    *,
    include_curves: bool,
) -> dict | None:
    if not sensor_bar_name:
        return None

    pdf_path = resources_dir / f"{sensor_bar_name}.pdf"
    if not pdf_path.exists():
        return {
            "name": sensor_bar_name,
            "status": "missing_pdf",
            "pdf_path": str(pdf_path),
        }

    return inspect_pdf_asset(
        pdf_path,
        asset_name=sensor_bar_name,
        include_curves=include_curves,
        inspect_raster_bounds=True,
    )


def inspect_framebuffer_mask_asset(
    resources_dir: Path,
    framebuffer_mask_name: str | None,
    *,
    include_curves: bool,
) -> dict | None:
    if not framebuffer_mask_name:
        return None

    pdf_path = resources_dir / f"{framebuffer_mask_name}.pdf"
    if not pdf_path.exists():
        return {
            "name": framebuffer_mask_name,
            "status": "missing_pdf",
            "pdf_path": str(pdf_path),
        }

    return inspect_pdf_asset(
        pdf_path,
        asset_name=framebuffer_mask_name,
        include_curves=include_curves,
        inspect_raster_bounds=False,
    )


def build_cutout_summary(
    supports_dynamic_island: bool,
    sensor_asset: dict | None,
) -> dict:
    summary = {
        "source": None,
        "available": False,
        "width_points": None,
        "height_points": None,
        "top_inset_points": None,
        "note": None,
    }

    if not sensor_asset:
        summary["source"] = "none"
        summary["note"] = "No sensor bar asset was declared in the device bundle."
        return summary

    opaque_bounds = sensor_asset.get("opaque_bounds_points")
    page_size = sensor_asset.get("page_size_points")

    if opaque_bounds:
        summary["source"] = "sensor_bar_pdf"
        summary["available"] = True
        summary["width_points"] = opaque_bounds["width"]
        summary["height_points"] = opaque_bounds["height"]
        summary["top_inset_points"] = 0
        summary["note"] = (
            "Derived from the drawable simulator sensor-bar PDF shipped with the "
            "device type."
        )
        return summary

    if supports_dynamic_island:
        summary["source"] = "dynamic_island_declared_but_blank_asset"
        if page_size:
            summary["width_points"] = page_size["width"]
            summary["height_points"] = page_size["height"]
        summary["note"] = (
            "The simulator bundle declares Dynamic Island support, but the shipped "
            "sensor-bar PDF is blank, so the exact island silhouette is not exposed "
            "directly by this package."
        )
        return summary

    summary["source"] = "blank_sensor_bar_pdf"
    if page_size:
        summary["width_points"] = page_size["width"]
        summary["height_points"] = page_size["height"]
    summary["note"] = (
        "A sensor-bar PDF exists, but it rendered with no opaque pixels."
    )
    return summary


def inspect_device_bundle(bundle_path: Path, *, include_curves: bool) -> dict | None:
    resources_dir = bundle_path / "Contents/Resources"
    profile_path = resources_dir / "profile.plist"
    capabilities_path = resources_dir / "capabilities.plist"

    if not profile_path.exists() or not capabilities_path.exists():
        return None

    profile = parse_plist(profile_path)
    capabilities_root = parse_plist(capabilities_path)
    capabilities = capabilities_root.get("capabilities", {})

    supported_families = profile.get("supportedProductFamilyIDs", [])
    if 1 not in supported_families:
        return None

    screen_width_px = int(profile["mainScreenWidth"])
    screen_height_px = int(profile["mainScreenHeight"])
    scale = float(profile["mainScreenScale"])

    sensor_asset = inspect_sensor_bar_asset(
        resources_dir,
        profile.get("sensorBarImage"),
        include_curves=include_curves,
    )
    framebuffer_mask_asset = inspect_framebuffer_mask_asset(
        resources_dir,
        profile.get("framebufferMask"),
        include_curves=include_curves,
    )
    supports_dynamic_island = bool(capabilities.get("DeviceSupportsDynamicIsland"))

    result = {
        "name": bundle_path.name.removesuffix(".simdevicetype"),
        "bundle_path": str(bundle_path),
        "model_identifier": profile.get("modelIdentifier") or capabilities.get("modelIdentifier"),
        "product_class": profile.get("productClass"),
        "marketing_name": capabilities.get("marketing-name"),
        "screen": {
            "pixels": {
                "width": screen_width_px,
                "height": screen_height_px,
            },
            "points": {
                "width": round_number(screen_width_px / scale),
                "height": round_number(screen_height_px / scale),
            },
            "scale": round_number(scale),
            "dpi": round_number(float(profile.get("mainScreenWidthDPI", 0))) if profile.get("mainScreenWidthDPI") else None,
            "main_screen_class": capabilities.get("ScreenDimensionsCapability", {}).get("main-screen-class"),
        },
        "chrome_identifier": profile.get("chromeIdentifier"),
        "supports_dynamic_island": supports_dynamic_island,
        "corner_radius_points": capabilities.get("DeviceCornerRadius"),
        "sensor_bar_asset": sensor_asset,
        "framebuffer_mask_asset": framebuffer_mask_asset,
        "top_cutout": build_cutout_summary(supports_dynamic_island, sensor_asset),
    }

    return result


def iter_device_bundles(paths: Iterable[Path]) -> list[Path]:
    bundles: dict[str, Path] = {}
    for path in paths:
        for bundle in find_simdevicetype_roots(path):
            bundles[str(bundle)] = bundle
    return sorted(bundles.values(), key=lambda item: item.name.lower())


def bundle_matches_name_filter(bundle: Path, needle: str | None) -> bool:
    if not needle:
        return True

    lowered = needle.lower()
    if lowered in bundle.name.lower():
        return True

    resources_dir = bundle / "Contents/Resources"
    for plist_name in ("profile.plist", "capabilities.plist"):
        plist_path = resources_dir / plist_name
        if not plist_path.exists():
            continue
        try:
            payload = parse_plist(plist_path)
        except Exception:
            continue

        values = []
        if plist_name == "profile.plist":
            values.extend(
                [
                    payload.get("modelIdentifier"),
                    payload.get("productClass"),
                ]
            )
        else:
            capabilities = payload.get("capabilities", {})
            values.extend(
                [
                    capabilities.get("modelIdentifier"),
                    capabilities.get("marketing-name"),
                ]
            )

        haystack = " ".join(str(value) for value in values if value).lower()
        if lowered in haystack:
            return True

    return False


def default_search_paths() -> list[Path]:
    return [Path("/Library/Developer/CoreSimulator/Profiles/DeviceTypes")]


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Extract screen and top-cutout metadata from simulator device packages."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help=(
            "A .dmg, DeviceTypes directory, *.simdevicetype bundle, or any root "
            "directory to search recursively."
        ),
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON output.",
    )
    parser.add_argument(
        "--name-filter",
        default=None,
        help="Only include devices whose name or model identifier contains this string.",
    )
    parser.add_argument(
        "--include-curves",
        action="store_true",
        help="Include full PDF path commands for vector assets in the JSON output.",
    )
    return parser


def main() -> None:
    if shutil.which("sips") is None:
        fail("This script requires macOS `sips`, but it was not found in PATH.")

    parser = build_argument_parser()
    args = parser.parse_args()

    raw_paths = args.paths or default_search_paths()
    mounted_dmgs: list[MountedDMG] = []
    search_paths: list[Path] = []

    try:
        for path in raw_paths:
            if path.is_file() and path.suffix == ".dmg":
                mounted = mount_dmg(path)
                mounted_dmgs.append(mounted)
                search_paths.append(mounted.mount_point)
            else:
                search_paths.append(path)

        bundles = iter_device_bundles(search_paths)
        if not bundles:
            fail(
                "No *.simdevicetype bundles were found. Note that an iOS runtime .dmg "
                "usually contains the runtime root, not the shared DeviceTypes catalog."
            )

        devices = []
        needle = args.name_filter
        for bundle in bundles:
            if not bundle_matches_name_filter(bundle, needle):
                continue

            inspected = inspect_device_bundle(bundle, include_curves=args.include_curves)
            if not inspected:
                continue

            devices.append(inspected)

        output = {
            "device_count": len(devices),
            "devices": devices,
        }

        json.dump(output, sys.stdout, indent=2 if args.pretty else None, sort_keys=False)
        sys.stdout.write("\n")
    finally:
        for mounted in reversed(mounted_dmgs):
            unmount_dmg(mounted)


if __name__ == "__main__":
    main()
