#!/usr/bin/env python3

"""
Fetch all iPhone simulator device assets into ./fetch_result.

What it does:
1. Reads every iPhone *.simdevicetype bundle from CoreSimulator
2. Creates ./fetch_result
3. Copies the relevant source files for each device:
   - profile.plist
   - capabilities.plist
   - sensor bar PDF if present
   - hardware screen curve PDF if present
4. Writes a pretty JSON manifest to ./fetch_result/devices.json

The JSON includes vector curve commands parsed from the PDFs.
"""

from __future__ import annotations

import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zlib
import hashlib
from pathlib import Path


DEVICE_TYPES_ROOT = Path("/Library/Developer/CoreSimulator/Profiles/DeviceTypes")
REPO_ROOT = Path(__file__).resolve().parent
OUTPUT_ROOT = REPO_ROOT / "fetch_result"
DEVICES_OUTPUT_ROOT = OUTPUT_ROOT / "devices"
MANIFEST_PATH = OUTPUT_ROOT / "devices.json"
SIMULATOR_DYNAMIC_ISLAND_INFO_PATH = REPO_ROOT / "simulator_dynamic_island_info.json"
IPHONE_DEVICE_SWIFT_PATH = REPO_ROOT / "Sources/TopCutout/iPhoneDevice.generated.swift"
IPHONE_DEVICE_PATH_SWIFT_PATH = REPO_ROOT / "Sources/TopCutout/iPhoneDevice+Path.generated.swift"
IPHONE_DEVICE_SCREEN_INFO_SWIFT_PATH = REPO_ROOT / "Sources/TopCutout/iPhoneDevice+ScreenInfo.generated.swift"
IPHONE_DEVICE_DISPLAY_NAME_SWIFT_PATH = REPO_ROOT / "Sources/TopCutout/iPhoneDevice+DisplayName.generated.swift"

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


def fail(message: str) -> "Never":
    print(message, file=sys.stderr)
    raise SystemExit(1)


def run_command(args: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(args, check=True, capture_output=True)


def parse_plist(path: Path) -> dict:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def round_number(value: float) -> float | int:
    rounded = round(value)
    if abs(value - rounded) < 1e-9:
        return int(rounded)
    return round(value, 4)


def slugify(value: str) -> str:
    value = value.lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


def relative_to_output(path: Path) -> str:
    return str(path.relative_to(OUTPUT_ROOT))


def copy_file(src: Path, dst_dir: Path) -> Path:
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / src.name
    shutil.copy2(src, dst)
    return dst


def load_simulator_dynamic_island_info() -> dict[str, dict]:
    if not SIMULATOR_DYNAMIC_ISLAND_INFO_PATH.exists():
        return {}

    with SIMULATOR_DYNAMIC_ISLAND_INFO_PATH.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    devices = payload.get("devices", payload)
    if not isinstance(devices, dict):
        fail(
            "simulator_dynamic_island_info.json must be an object or contain a top-level 'devices' object"
        )

    result: dict[str, dict] = {}
    for model_identifier, device_info in devices.items():
        if not isinstance(device_info, dict):
            continue

        probe_report = device_info.get("probe_report", device_info)
        if not isinstance(probe_report, dict):
            continue

        exclusion_rect = probe_report.get("exclusionRect")
        if not isinstance(exclusion_rect, dict):
            continue

        try:
            width = round_number(float(exclusion_rect["width"]))
            height = round_number(float(exclusion_rect["height"]))
            top = round_number(float(exclusion_rect["y"]))
        except (KeyError, TypeError, ValueError):
            continue

        result[model_identifier] = {
            "device_name": device_info.get("device_name") or probe_report.get("deviceName"),
            "probe_report": probe_report,
            "size_points": {
                "width": width,
                "height": height,
            },
            "padding_top_points": top,
        }

    return result


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

        compressed = data[stream_start:stream_end].rstrip(b"\r\n")
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
            if len(number_stack) < arity:
                number_stack.clear()
                continue

            args = number_stack[-arity:] if arity else []
            if arity:
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
    if not commands:
        return {
            "command_count": 0,
            "subpath_count": 0,
            "has_beziers": False,
            "operators": [],
            "commands": [],
        }

    operators = [command["op"] for command in commands]
    return {
        "command_count": len(commands),
        "subpath_count": sum(1 for op in operators if op in {"m", "re"}),
        "has_beziers": any(op in {"c", "v", "y"} for op in operators),
        "operators": sorted(set(operators)),
        "commands": commands,
    }


def inspect_pdf_vector_paths(pdf_path: Path) -> list[list[dict]]:
    path_streams = [
        stream
        for stream in extract_pdf_flate_streams(pdf_path)
        if looks_like_pdf_path_stream(stream)
    ]

    parsed_streams = []
    for stream in path_streams:
        commands = parse_pdf_path_commands(stream)
        if commands:
            parsed_streams.append(commands)

    return parsed_streams


def extract_primary_path_commands(commands: list[dict]) -> list[dict]:
    stop_ops = {"W", "W*", "n", "f", "f*", "F", "B", "B*", "b", "b*", "S", "s"}
    primary: list[dict] = []
    for command in commands:
        if command["op"] in stop_ops:
            break
        primary.append(command)
    return primary


def path_signature(commands: list[dict]) -> str:
    payload = json.dumps(commands, separators=(",", ":"), sort_keys=True)
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()


def commands_to_swift_path_body_lines(
    commands: list[dict],
    *,
    indent: str,
) -> list[str]:
    lines = [f"{indent}var path = Path()"]

    current_point: tuple[float | int, float | int] | None = None
    subpath_start: tuple[float | int, float | int] | None = None

    def point_literal(x: float | int, y: float | int) -> str:
        return f"CGPoint(x: {x}, y: {y})"

    for command in commands:
        op = command["op"]
        args = command["args"]

        if op == "m":
            point = (args[0], args[1])
            lines.append(f"{indent}path.move(to: {point_literal(*point)})")
            current_point = point
            subpath_start = point
        elif op == "l":
            point = (args[0], args[1])
            lines.append(f"{indent}path.addLine(to: {point_literal(*point)})")
            current_point = point
        elif op == "c":
            end_point = (args[4], args[5])
            lines.append(
                f"{indent}path.addCurve("
                f"to: {point_literal(*end_point)}, "
                f"control1: {point_literal(args[0], args[1])}, "
                f"control2: {point_literal(args[2], args[3])}"
                ")"
            )
            current_point = end_point
        elif op == "v" and current_point is not None:
            end_point = (args[2], args[3])
            lines.append(
                f"{indent}path.addCurve("
                f"to: {point_literal(*end_point)}, "
                f"control1: {point_literal(*current_point)}, "
                f"control2: {point_literal(args[0], args[1])}"
                ")"
            )
            current_point = end_point
        elif op == "y":
            end_point = (args[2], args[3])
            lines.append(
                f"{indent}path.addCurve("
                f"to: {point_literal(*end_point)}, "
                f"control1: {point_literal(args[0], args[1])}, "
                f"control2: {point_literal(*end_point)}"
                ")"
            )
            current_point = end_point
        elif op == "h":
            lines.append(f"{indent}path.closeSubpath()")
            current_point = subpath_start
        elif op == "re":
            lines.append(
                f"{indent}path.addRect("
                f"CGRect(x: {args[0]}, y: {args[1]}, width: {args[2]}, height: {args[3]})"
                ")"
            )
            current_point = None
            subpath_start = None

    lines.append(f"{indent}return path")
    return lines


def swift_number_literal(value: float | int | None) -> str:
    if value is None:
        return "nil"
    if isinstance(value, int):
        return str(value)

    rounded = round(value)
    if abs(value - rounded) < 1e-9:
        return str(int(rounded))
    return repr(value)


def display_name_for_device(device: dict) -> str:
    device_name = device["device_name"]
    marketing_name = device.get("marketing_name")
    if not marketing_name:
        return device_name

    # Keep generation detail for SE models while using cleaner marketing casing elsewhere.
    if marketing_name == "iPhone SE" and "(" in device_name:
        return device_name

    return marketing_name


def swift_top_feature_kind_literal(kind: str) -> str:
    if kind == "none":
        return ".none"
    if kind == "notch":
        return ".notch"
    if kind == "dynamic_island":
        return ".dynamicIsland"
    fail(f"Unsupported top feature kind: {kind}")


def swift_bool_literal(value: bool) -> str:
    return "true" if value else "false"


def write_swift_paths_file(
    devices: dict[str, dict],
    model_to_function: dict[str, str],
    function_to_commands: dict[str, list[dict]],
) -> None:
    lines = [
        "import SwiftUI",
        "",
        "// Generated by inspect_simulator_topcutouts.py",
        "extension IPhoneDevice {",
        "    public var topFeaturePath: Path? {",
        "        switch self {",
    ]

    for model_identifier, device in sorted(devices.items(), key=lambda item: model_identifier_sort_key(item[0])):
        case_name = swift_enum_case_name(device["device_name"])
        function_name = model_to_function.get(model_identifier)
        if function_name is None:
            continue

        commands = function_to_commands[function_name]
        lines.append(f"        case .{case_name}:")
        lines.extend(commands_to_swift_path_body_lines(commands, indent="            "))

    lines.extend(
        [
            "        default:",
            "            return nil",
            "        }",
            "    }",
        ]
    )

    lines.append("}")
    IPHONE_DEVICE_PATH_SWIFT_PATH.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def swift_enum_case_name(device_name: str) -> str:
    normalized = device_name.replace("ʀ", "R")
    tokens = re.findall(r"[A-Za-z0-9]+", normalized)
    if not tokens:
        fail(f"Could not derive a Swift enum case name from device name: {device_name}")

    parts: list[str] = []
    for index, token in enumerate(tokens):
        if index == 0 and token.lower() == "iphone":
            parts.append("iPhone")
        elif token.isupper() or token[0].isdigit():
            parts.append(token)
        else:
            parts.append(token[0].upper() + token[1:])

    return "".join(parts)


def model_identifier_sort_key(model_identifier: str) -> tuple[tuple[int, int | str], ...]:
    normalized = model_identifier.removeprefix("iPhone")
    parts = normalized.split(",")
    key: list[tuple[int, int | str]] = []
    for part in parts:
        try:
            key.append((0, int(part)))
        except ValueError:
            key.append((1, part))
    return tuple(key)


def write_swift_device_enum_file(devices: dict[str, dict]) -> None:
    lines = [
        "// Generated by inspect_simulator_topcutouts.py",
        "public enum IPhoneDevice: String, CaseIterable, Sendable {",
    ]

    seen_case_names: dict[str, str] = {}
    sorted_devices = sorted(devices.items(), key=lambda item: model_identifier_sort_key(item[0]))
    for model_identifier, device in sorted_devices:
        case_name = swift_enum_case_name(device["device_name"])
        duplicate = seen_case_names.get(case_name)
        if duplicate is not None:
            fail(
                "Duplicate Swift enum case name "
                f"{case_name!r} for model identifiers {duplicate} and {model_identifier}"
            )

        seen_case_names[case_name] = model_identifier
        lines.append(f'    case {case_name} = "{model_identifier}"')

    lines.append("}")
    IPHONE_DEVICE_SWIFT_PATH.write_text(
        "\n".join(lines).rstrip() + "\n",
        encoding="utf-8",
    )


def write_swift_screen_info_file(devices: dict[str, dict]) -> None:
    lines = [
        "import UIKit",
        "",
        "// Generated by inspect_simulator_topcutouts.py",
        "extension IPhoneDevice {",
        "    public var screenInfo: IPhoneScreenInfo {",
        "        switch self {",
    ]

    for model_identifier, device in sorted(devices.items(), key=lambda item: model_identifier_sort_key(item[0])):
        case_name = swift_enum_case_name(device["device_name"])
        screen = device["screen"]
        pixels = screen["pixels"]
        points = screen["points"]
        corner_radius_points = swift_number_literal(screen["corner_radius_points"])
        dpi = screen["dpi"]
        scale = swift_number_literal(screen["scale"])
        point_width = swift_number_literal(points["width"])
        point_height = swift_number_literal(points["height"])
        top_feature = device["top_feature"]
        size_points = top_feature["size_points"]
        padding_top_points = top_feature["padding_top_points"]

        lines.extend(
            [
                f"        case .{case_name}:",
                "            return IPhoneScreenInfo(",
                f"                cornerRadiusPoints: {corner_radius_points},",
                f"                dpi: {dpi if dpi is not None else 'nil'},",
                "                pixels: CGSize(",
                f"                    width: {pixels['width']},",
                f"                    height: {pixels['height']}",
                "                ),",
                "                points: CGSize(",
                f"                    width: {point_width},",
                f"                    height: {point_height}",
                "                ),",
                f"                scale: {scale},",
                "                topFeature: IPhoneTopFeatureInfo(",
                f"                    kind: {swift_top_feature_kind_literal(top_feature['kind'])},",
                f"                    geometryAvailable: {swift_bool_literal(top_feature['geometry_available'])},",
                f"                    curveAvailable: {swift_bool_literal(top_feature['curve_available'])},",
            ]
        )

        if size_points is None:
            lines.append("                    size: nil,")
        else:
            lines.extend(
                [
                    "                    size: CGSize(",
                    f"                        width: {swift_number_literal(size_points['width'])},",
                    f"                        height: {swift_number_literal(size_points['height'])}",
                    "                    ),",
                ]
            )

        lines.extend(
            [
                f"                    paddingTop: {swift_number_literal(padding_top_points)}",
                "                )",
                "            )",
            ]
        )

    lines.extend(
        [
            "        }",
            "    }",
            "}",
        ]
    )

    IPHONE_DEVICE_SCREEN_INFO_SWIFT_PATH.write_text(
        "\n".join(lines).rstrip() + "\n",
        encoding="utf-8",
    )


def write_swift_display_name_file(devices: dict[str, dict]) -> None:
    lines = [
        "// Generated by inspect_simulator_topcutouts.py",
        "extension IPhoneDevice {",
        "    public var displayName: String {",
        "        switch self {",
    ]

    for model_identifier, device in sorted(devices.items(), key=lambda item: model_identifier_sort_key(item[0])):
        case_name = swift_enum_case_name(device["device_name"])
        lines.append(f"        case .{case_name}:")
        lines.append(f'            return "{display_name_for_device(device)}"')

    lines.extend(
        [
            "        }",
            "    }",
            "}",
        ]
    )

    IPHONE_DEVICE_DISPLAY_NAME_SWIFT_PATH.write_text(
        "\n".join(lines).rstrip() + "\n",
        encoding="utf-8",
    )


def rasterize_pdf_to_png(pdf_path: Path, png_path: Path) -> None:
    run_command(["sips", "-s", "format", "png", str(pdf_path), "--out", str(png_path)])


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
        position += length + 4

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
        raise ValueError(f"{png_path} uses unsupported PNG bit depth {bit_depth}")

    channels_by_color_type = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
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
                if len(trns) >= 6 and (red, green, blue) == (trns[1], trns[3], trns[5]):
                    alpha = 0
            elif color_type == 3:
                index = row[start]
                alpha = trns[index] if index < len(trns) else 255
            elif color_type == 4:
                alpha = row[start + 1]
            else:
                alpha = row[start + 3]

            if alpha > 0:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)

        previous_row = row

    if max_x < 0:
        return None

    return {
        "x": min_x,
        "y": min_y,
        "width": max_x - min_x + 1,
        "height": max_y - min_y + 1,
    }


def inspect_pdf_asset(
    pdf_path: Path,
    *,
    asset_name: str,
    inspect_raster_bounds: bool,
) -> dict:
    page_size = parse_pdf_media_box(pdf_path)

    opaque_bounds = None
    status = "pdf_present"
    if inspect_raster_bounds:
        with tempfile.TemporaryDirectory(prefix="sim-topcutout-") as temp_dir:
            png_path = Path(temp_dir) / f"{asset_name}.png"
            rasterize_pdf_to_png(pdf_path, png_path)
            opaque_bounds = decode_png_alpha_bbox(png_path)
        status = "rendered" if opaque_bounds else "blank_pdf"

    result = {
        "name": asset_name,
        "status": status,
        "page_size_points": None,
    }

    if inspect_raster_bounds:
        result["opaque_bounds_points"] = opaque_bounds

    if page_size:
        result["page_size_points"] = {
            "width": round_number(page_size[0]),
            "height": round_number(page_size[1]),
        }

    return result


def inspect_device_bundle(
    bundle_path: Path,
    *,
    simulator_dynamic_island_info: dict[str, dict],
) -> dict | None:
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
    if capabilities.get("idiom") != "phone":
        return None

    device_name = bundle_path.name.removesuffix(".simdevicetype")
    if not device_name.startswith("iPhone"):
        return None
    device_dir = DEVICES_OUTPUT_ROOT / slugify(device_name)
    device_dir.mkdir(parents=True, exist_ok=True)

    copy_file(profile_path, device_dir)
    copy_file(capabilities_path, device_dir)

    sensor_bar_name = profile.get("sensorBarImage")
    sensor_bar_asset = None
    if sensor_bar_name:
        sensor_bar_pdf = resources_dir / f"{sensor_bar_name}.pdf"
        if sensor_bar_pdf.exists():
            copy_file(sensor_bar_pdf, device_dir)
            sensor_bar_asset = inspect_pdf_asset(
                sensor_bar_pdf,
                asset_name=sensor_bar_name,
                inspect_raster_bounds=True,
            )
        else:
            sensor_bar_asset = {
                "name": sensor_bar_name,
                "status": "missing_pdf",
            }

    framebuffer_mask_name = profile.get("framebufferMask")
    if framebuffer_mask_name:
        screen_curve_pdf = resources_dir / f"{framebuffer_mask_name}.pdf"
        if screen_curve_pdf.exists():
            copy_file(screen_curve_pdf, device_dir)
            inspect_pdf_asset(
                screen_curve_pdf,
                asset_name=framebuffer_mask_name,
                inspect_raster_bounds=False,
            )

    supports_dynamic_island = bool(capabilities.get("DeviceSupportsDynamicIsland"))
    if supports_dynamic_island:
        top_kind = "dynamic_island"
    elif sensor_bar_name:
        top_kind = "notch"
    else:
        top_kind = "none"

    top_size = None
    top_padding = None
    top_curve_available = False
    primary_top_feature_commands: list[dict] = []

    if sensor_bar_asset and sensor_bar_asset.get("status") == "rendered":
        opaque_bounds = sensor_bar_asset.get("opaque_bounds_points")
        if opaque_bounds:
            top_size = {
                "width": opaque_bounds["width"],
                "height": opaque_bounds["height"],
            }
            top_padding = 0
        if sensor_bar_name:
            sensor_bar_pdf = resources_dir / f"{sensor_bar_name}.pdf"
            path_streams = inspect_pdf_vector_paths(sensor_bar_pdf)
            if path_streams:
                primary_top_feature_commands = extract_primary_path_commands(path_streams[0])
                top_curve_available = bool(primary_top_feature_commands)

    screen_width_px = int(profile["mainScreenWidth"])
    screen_height_px = int(profile["mainScreenHeight"])
    scale = float(profile["mainScreenScale"])
    model_identifier = profile.get("modelIdentifier") or capabilities.get("modelIdentifier")

    simulator_dynamic_island_probe = simulator_dynamic_island_info.get(model_identifier)
    if simulator_dynamic_island_probe is not None and top_kind == "dynamic_island":
        top_size = simulator_dynamic_island_probe["size_points"]
        top_padding = simulator_dynamic_island_probe["padding_top_points"]

    return {
        "device_name": device_name,
        "marketing_name": capabilities.get("marketing-name"),
        "model_identifier": model_identifier,
        "product_class": profile.get("productClass"),
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
            "corner_radius_points": capabilities.get("DeviceCornerRadius"),
        },
        "top_feature": {
            "kind": top_kind,
            "geometry_available": top_size is not None,
            "curve_available": top_curve_available,
            "size_points": top_size,
            "padding_top_points": top_padding,
        },
        "top_feature_asset": sensor_bar_asset,
        "top_feature_simulator_probe": simulator_dynamic_island_probe,
        "_top_feature_asset_name": sensor_bar_name,
        "_top_feature_primary_commands": primary_top_feature_commands,
    }


def main() -> None:
    if shutil.which("sips") is None:
        fail("This script requires macOS `sips`, but it was not found in PATH.")

    if not DEVICE_TYPES_ROOT.is_dir():
        fail(f"Simulator device types were not found at {DEVICE_TYPES_ROOT}")

    if OUTPUT_ROOT.exists():
        shutil.rmtree(OUTPUT_ROOT)
    DEVICES_OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)

    simulator_dynamic_island_info = load_simulator_dynamic_island_info()
    if simulator_dynamic_island_info:
        print(
            "Loaded "
            f"{len(simulator_dynamic_island_info)} simulator Dynamic Island records from "
            f"{SIMULATOR_DYNAMIC_ISLAND_INFO_PATH}"
        )

    devices: dict[str, dict] = {}
    model_to_function: dict[str, str] = {}
    signature_to_function: dict[str, str] = {}
    function_to_commands: dict[str, list[dict]] = {}
    for bundle_path in sorted(DEVICE_TYPES_ROOT.glob("*.simdevicetype"), key=lambda item: item.name.lower()):
        inspected = inspect_device_bundle(
            bundle_path,
            simulator_dynamic_island_info=simulator_dynamic_island_info,
        )
        if inspected:
            model_identifier = inspected["model_identifier"]
            inspected.pop("_top_feature_asset_name", None)
            primary_commands = inspected.pop("_top_feature_primary_commands", [])

            if primary_commands:
                signature = path_signature(primary_commands)
                function_name = signature_to_function.get(signature)
                if function_name is None:
                    function_name = f"topFeatureVariant{len(signature_to_function) + 1:02d}"
                    signature_to_function[signature] = function_name
                    function_to_commands[function_name] = primary_commands
                model_to_function[model_identifier] = function_name

            devices[model_identifier] = inspected

    manifest_devices = {
        model_identifier: {
            key: value
            for key, value in device.items()
            if key
            not in {
                "device_name",
                "marketing_name",
                "product_class",
                "screen",
                "top_feature_asset",
                "top_feature_simulator_probe",
            }
        }
        for model_identifier, device in devices.items()
    }

    with MANIFEST_PATH.open("w", encoding="utf-8") as handle:
        json.dump(manifest_devices, handle, indent=2, ensure_ascii=True, sort_keys=True)
        handle.write("\n")

    write_swift_paths_file(devices, model_to_function, function_to_commands)
    write_swift_device_enum_file(devices)
    write_swift_screen_info_file(devices)
    write_swift_display_name_file(devices)
    print(f"Wrote {MANIFEST_PATH}")


if __name__ == "__main__":
    main()
