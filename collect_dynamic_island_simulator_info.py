#!/usr/bin/env python3

from __future__ import annotations

import json
import plistlib
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path


DEVICE_TYPES_ROOT = Path("/Library/Developer/CoreSimulator/Profiles/DeviceTypes")
REPO_ROOT = Path(__file__).resolve().parent
OUTPUT_PATH = REPO_ROOT / "simulator_dynamic_island_info.json"
INSPECT_SCRIPT = REPO_ROOT / "inspect_simulator_topcutouts.py"
DERIVED_DATA_PATH = Path("/tmp/TopCutoutDerived")
APP_BUNDLE_PATH = DERIVED_DATA_PATH / "Build/Products/Debug-iphonesimulator/TopCutoutDemo.app"
BUNDLE_ID = "demo.TopCutoutDemo"
REPORT_RELATIVE_PATH = Path("Documents/TopCutoutProbeReport.json")


def fail(message: str) -> "Never":
    print(message, file=sys.stderr)
    raise SystemExit(1)


def run_command(args: list[str], *, text: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(args, check=True, capture_output=True, text=text)
    except subprocess.CalledProcessError as error:
        detail = error.stderr or error.stdout or str(error)
        fail(f"Command failed: {' '.join(args)}\n{detail}")


def parse_plist(path: Path) -> dict:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def parse_version(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in value.split("."))


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


def latest_ios_runtime() -> dict:
    payload = json.loads(run_command(["xcrun", "simctl", "runtime", "list", "-j"]).stdout)
    runtimes = [
        runtime
        for runtime in payload.values()
        if runtime.get("platformIdentifier") == "com.apple.platform.iphonesimulator"
        and runtime.get("state") == "Ready"
    ]
    if not runtimes:
        fail("No ready iOS simulator runtime found.")

    return max(runtimes, key=lambda runtime: parse_version(runtime["version"]))


def dynamic_island_device_types() -> list[dict]:
    result: list[dict] = []
    for bundle_path in sorted(DEVICE_TYPES_ROOT.glob("*.simdevicetype"), key=lambda item: item.name.lower()):
        resources_dir = bundle_path / "Contents/Resources"
        profile_path = resources_dir / "profile.plist"
        capabilities_path = resources_dir / "capabilities.plist"
        info_path = bundle_path / "Contents/Info.plist"

        if not profile_path.exists() or not capabilities_path.exists() or not info_path.exists():
            continue

        profile = parse_plist(profile_path)
        capabilities_root = parse_plist(capabilities_path)
        capabilities = capabilities_root.get("capabilities", {})

        if capabilities.get("idiom") != "phone":
            continue
        if not capabilities.get("DeviceSupportsDynamicIsland"):
            continue

        info = parse_plist(info_path)
        model_identifier = profile.get("modelIdentifier") or capabilities.get("modelIdentifier")
        if not model_identifier:
            continue

        result.append(
            {
                "device_name": bundle_path.name.removesuffix(".simdevicetype"),
                "device_type_identifier": info["CFBundleIdentifier"],
                "model_identifier": model_identifier,
                "chrome_identifier": profile.get("chromeIdentifier"),
                "framebuffer_identifier": profile.get("framebufferMask"),
                "sensor_bar_image": profile.get("sensorBarImage"),
            }
        )

    return sorted(result, key=lambda item: model_identifier_sort_key(item["model_identifier"]))


def create_temporary_device(device_type: dict, runtime_identifier: str) -> str:
    temp_name = f"TopCutout Probe {device_type['device_name']} {uuid.uuid4().hex[:8]}"
    return run_command(
        [
            "xcrun",
            "simctl",
            "create",
            temp_name,
            device_type["device_type_identifier"],
            runtime_identifier,
        ]
    ).stdout.strip()


def boot_device(device_id: str) -> None:
    run_command(["xcrun", "simctl", "boot", device_id])
    run_command(["xcrun", "simctl", "bootstatus", device_id, "-b"])


def shutdown_device(device_id: str) -> None:
    subprocess.run(
        ["xcrun", "simctl", "shutdown", device_id],
        check=False,
        capture_output=True,
        text=True,
    )


def delete_device(device_id: str) -> None:
    subprocess.run(
        ["xcrun", "simctl", "delete", device_id],
        check=False,
        capture_output=True,
        text=True,
    )


def build_probe_app(device_id: str) -> None:
    run_command(
        [
            "xcodebuild",
            "-project",
            str(REPO_ROOT / "TopCutoutDemo/TopCutoutDemo.xcodeproj"),
            "-scheme",
            "TopCutoutDemo",
            "-configuration",
            "Debug",
            "-destination",
            f"platform=iOS Simulator,id={device_id}",
            "-derivedDataPath",
            str(DERIVED_DATA_PATH),
            "build",
        ]
    )

    if not APP_BUNDLE_PATH.exists():
        fail(f"Expected built app at {APP_BUNDLE_PATH}, but it was not found.")


def collect_probe_report(device_id: str) -> dict:
    run_command(["xcrun", "simctl", "install", device_id, str(APP_BUNDLE_PATH)])
    report_path = (
        Path(
            run_command(
                ["xcrun", "simctl", "get_app_container", device_id, BUNDLE_ID, "data"]
            ).stdout.strip()
        )
        / REPORT_RELATIVE_PATH
    )

    written_after = time.time()
    run_command(["xcrun", "simctl", "launch", "--terminate-running-process", device_id, BUNDLE_ID])

    deadline = time.time() + 20.0
    while time.time() < deadline:
        if report_path.exists():
            stat = report_path.stat()
            if stat.st_mtime >= written_after:
                contents = report_path.read_text(encoding="utf-8").strip()
                if contents:
                    return json.loads(contents)
        time.sleep(0.25)

    fail(f"Timed out waiting for probe report at {report_path}")


def write_output(runtime: dict, devices: dict[str, dict]) -> None:
    payload = {
        "runtime_identifier": runtime["runtimeIdentifier"],
        "runtime_version": runtime["version"],
        "devices": devices,
    }
    OUTPUT_PATH.write_text(
        json.dumps(payload, indent=2, ensure_ascii=True, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def load_existing_output() -> dict:
    if not OUTPUT_PATH.exists():
        return {}

    with OUTPUT_PATH.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    devices = payload.get("devices", {})
    if not isinstance(devices, dict):
        fail(f"{OUTPUT_PATH} has an invalid 'devices' payload.")

    return devices


def regenerate_generated_files() -> None:
    run_command([sys.executable, str(INSPECT_SCRIPT)])


def main() -> None:
    if shutil.which("xcrun") is None:
        fail("xcrun was not found in PATH.")

    runtime = latest_ios_runtime()
    dynamic_island_devices = dynamic_island_device_types()
    if not dynamic_island_devices:
        fail("No Dynamic Island simulator device types were found.")

    print(
        f"Using iOS simulator runtime {runtime['version']} "
        f"({runtime['runtimeIdentifier']}) for {len(dynamic_island_devices)} Dynamic Island device types."
    )

    collected = load_existing_output()
    if collected:
        print(f"Resuming with {len(collected)} existing records from {OUTPUT_PATH}.")

    build_device_id: str | None = None

    for index, device_type in enumerate(dynamic_island_devices):
        model_identifier = device_type["model_identifier"]
        if model_identifier in collected:
            print(
                f"[{index + 1}/{len(dynamic_island_devices)}] "
                f"Skipping {model_identifier} ({device_type['device_name']}); already collected."
            )
            continue

        device_id = create_temporary_device(device_type, runtime["runtimeIdentifier"])
        try:
            boot_device(device_id)
            if build_device_id is None:
                build_probe_app(device_id)
                build_device_id = device_id

            probe_report = collect_probe_report(device_id)
            collected[model_identifier] = {
                "device_name": device_type["device_name"],
                "device_type_identifier": device_type["device_type_identifier"],
                "chrome_identifier": device_type["chrome_identifier"],
                "framebuffer_identifier": device_type["framebuffer_identifier"],
                "sensor_bar_image": device_type["sensor_bar_image"],
                "probe_report": probe_report,
            }
            write_output(runtime, collected)
            print(
                f"[{index + 1}/{len(dynamic_island_devices)}] "
                f"Collected {model_identifier} ({device_type['device_name']})"
            )
        finally:
            shutdown_device(device_id)
            delete_device(device_id)

    print(f"Wrote {OUTPUT_PATH}")

    regenerate_generated_files()
    print("Regenerated inspect_simulator_topcutouts.py outputs.")


if __name__ == "__main__":
    main()
