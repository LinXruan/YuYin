#!/usr/bin/env python3
"""无线 ADB 重连工具（Android 11+，含 Android 14）。

用法:
    python tool/adb_wifi.py                # 重连并打印结果
    python tool/adb_wifi.py --print-only   # 只输出 ip:port，供 bat 捕获
    python tool/adb_wifi.py --list         # 列出当前 adb 设备
    python tool/adb_wifi.py --serial ip:port

连接顺序:
    1. 已连接的网络设备
    2. adb mDNS 发现的 _adb-tls-connect._tcp
    3. 上次成功地址（tool/.adb_last_endpoint）
    4. USB 在场时自动 adb tcpip 5555 后连接

注意: 手机休眠/重启后无线调试可能自动关闭，需先在「开发者选项 > 无线调试」重新打开。
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".adb_last_endpoint")
MDNS_CONNECT = "_adb-tls-connect._tcp"


def find_adb() -> str:
    sdk = os.path.join(
        os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk", "platform-tools", "adb.exe"
    )
    if os.path.isfile(sdk):
        return sdk
    return shutil.which("adb") or "adb"


ADB = find_adb()
QUIET = False


def say(message: str) -> None:
    """--print-only 时保持 stdout 只有地址，其余信息走 stderr。"""
    print(message, file=sys.stderr if QUIET else sys.stdout)


def adb(args: list[str], timeout: int = 15) -> subprocess.CompletedProcess:
    return subprocess.run([ADB, *args], capture_output=True, text=True, timeout=timeout)


def devices() -> list[tuple[str, str]]:
    try:
        output = adb(["devices"]).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    rows = []
    for line in output.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2:
            rows.append((parts[0], parts[1]))
    return rows


def is_network(serial: str) -> bool:
    return ":" in serial and not serial.startswith("emulator-")


def is_usb(serial: str) -> bool:
    return ":" not in serial and not serial.startswith("emulator-")


def connect(endpoint: str) -> bool:
    result = adb(["connect", endpoint])
    message = (result.stdout + result.stderr).strip()
    if message:
        say(f"  {message}")
    return "connected to" in message or "already connected" in message


def load_cache() -> str | None:
    try:
        with open(CACHE, encoding="utf-8") as file:
            return file.read().strip() or None
    except OSError:
        return None


def save_cache(endpoint: str) -> None:
    try:
        with open(CACHE, "w", encoding="utf-8") as file:
            file.write(endpoint)
    except OSError:
        pass


def mdns_endpoints() -> list[str]:
    try:
        output = adb(["mdns", "services"], timeout=8).stdout
    except (subprocess.TimeoutExpired, OSError):
        return []
    endpoints = []
    for line in output.splitlines():
        if MDNS_CONNECT in line:
            token = line.split()[-1]
            if ":" in token:
                endpoints.append(token)
    return endpoints


def bootstrap_from_usb() -> str | None:
    usb = [serial for serial, state in devices() if state == "device" and is_usb(serial)]
    if not usb:
        return None
    serial = usb[0]
    say(f"发现 USB 设备 {serial}，开启无线调试端口 5555…")
    try:
        address = adb(
            ["-s", serial, "shell", "ip", "-f", "inet", "addr", "show", "wlan0"]
        ).stdout
    except subprocess.TimeoutExpired:
        return None
    match = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", address)
    if not match:
        say("  读取不到 wlan0 地址（手机是否连接 WiFi？）")
        return None
    endpoint = f"{match.group(1)}:5555"
    adb(["-s", serial, "tcpip", "5555"])
    time.sleep(1)
    say(f"  尝试连接 {endpoint}")
    return endpoint if connect(endpoint) else None


def ensure_connected(serial: str | None = None) -> str | None:
    if serial:
        if any(item == serial and state == "device" for item, state in devices()):
            return serial
        if is_network(serial) and connect(serial):
            save_cache(serial)
            return serial
        return None

    for item, state in devices():
        if is_network(item) and state == "device":
            say(f"已连接无线设备: {item}")
            return item

    for endpoint in mdns_endpoints():
        say(f"mDNS 发现 {endpoint}，尝试连接…")
        if connect(endpoint):
            save_cache(endpoint)
            return endpoint

    cached = load_cache()
    if cached:
        say(f"尝试上次地址 {cached}…")
        if connect(cached):
            return cached

    endpoint = bootstrap_from_usb()
    if endpoint:
        save_cache(endpoint)
        return endpoint
    return None


def main() -> int:
    global QUIET
    parser = argparse.ArgumentParser(description="无线 ADB 一键重连")
    parser.add_argument("--list", action="store_true", help="只列出当前 adb 设备")
    parser.add_argument("--serial", help="指定网络设备序列号 ip:port")
    parser.add_argument("--print-only", action="store_true", help="只输出 ip:port")
    args = parser.parse_args()
    QUIET = args.print_only

    if args.list:
        for serial, state in devices():
            print(f"{serial}\t{state}")
        return 0

    endpoint = ensure_connected(args.serial)
    if not endpoint:
        say("重连失败：请检查同一 WiFi、手机「无线调试」开关，或插一次数据线。")
        return 1
    say(f"无线 ADB 就绪: {endpoint}")
    if QUIET:
        print(endpoint)
    return 0


if __name__ == "__main__":
    sys.exit(main())