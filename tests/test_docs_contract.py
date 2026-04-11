#!/usr/bin/env python3

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require_contains(path: Path, needle: str):
    content = path.read_text(encoding="utf-8")
    assert needle in content, f"{path} missing: {needle}"


def require_not_contains(path: Path, needle: str):
    content = path.read_text(encoding="utf-8")
    assert needle not in content, f"{path} still contains stale text: {needle}"


def main():
    readme = ROOT / "README.md"
    openwrt_readme = ROOT / "OpenWrt" / "README.md"
    windows_ai = ROOT / "Windows" / "AIREADME.md"
    macos_ai = ROOT / "macOS" / "AIREADME.md"
    logging_contract = ROOT / "docs" / "LOGGING_CONTRACT.md"
    protocol_spec = ROOT / "docs" / "SRUN3K_PROTOCOL_SPEC.md"

    require_contains(readme, "HAUTNetworkGuard-Windows.zip")
    require_contains(readme, "HAUTNetworkGuard.dmg")
    require_contains(readme, "sh -s -- v1.3.16")
    require_contains(readme, "protocol_utils.h/cpp")
    require_contains(readme, "SrunProtocol.swift")
    require_contains(readme, "tests/")
    require_not_contains(readme, "HAUTNetworkGuard-Windows.exe")
    require_not_contains(readme, "HAUTNetworkGuard-macOS.dmg")

    require_contains(openwrt_readme, "HAUTNetworkGuard/main/OpenWrt/install-online.sh | sh")
    require_contains(openwrt_readme, "HAUTNetworkGuard/v1.3.16/OpenWrt/install-online.sh | sh -s -- v1.3.16")
    require_contains(openwrt_readme, "upgrade-online.sh | sh")
    require_contains(openwrt_readme, "log.lua")
    require_contains(openwrt_readme, "../docs/LOGGING_CONTRACT.md")

    require_contains(windows_ai, "版本号**: 1.3.16")
    require_contains(windows_ai, "172.16.154.130")
    require_contains(windows_ai, "protocol_utils.cpp")
    require_not_contains(windows_ai, "172.20.255.2")
    require_not_contains(windows_ai, "版本号**: 1.3.0")

    require_contains(macos_ai, "版本号**: 1.3.16")
    require_contains(macos_ai, "Logger.swift")
    require_contains(macos_ai, "SrunProtocol.swift")
    require_contains(macos_ai, "172.16.154.130")
    require_not_contains(macos_ai, "版本号**: 1.1.4")

    require_contains(logging_contract, "error_E####")
    require_contains(logging_contract, "online_jsonp")
    require_contains(protocol_spec, "error_E####")
    require_contains(protocol_spec, "Windows/tests/windows_smoke_tests.cpp")

    print("docs contract ok")


if __name__ == "__main__":
    main()
