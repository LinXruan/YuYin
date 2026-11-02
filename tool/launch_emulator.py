"""
YuYin 模拟器窗口可视化启动器 (launch_emulator.py)
解决反重力 (Antigravity) 运行环境下 Job Object 与虚拟沙盒桌面隔离导致模拟器窗口被隐藏或秒退的问题。
通过 Windows 交互式调度/跨桌面注入，确保在用户屏幕正中央呈现手机外观窗口，且不受 Agent 任务生命周期影响。
"""

import os
import sys
import time
import subprocess
from pathlib import Path

TASK_NAME = "YuYinEmulatorLauncher"

def is_emulator_running():
    try:
        res = subprocess.run(["adb", "devices"], capture_output=True, text=True, check=False)
        for line in res.stdout.splitlines():
            parts = line.strip().split()
            if len(parts) >= 2 and parts[0].startswith("emulator-") and parts[1] == "device":
                return True
    except Exception:
        pass
    return False

def clean_avd_locks():
    user_home = Path(os.environ.get("USERPROFILE", ""))
    avd_dir = user_home / ".android" / "avd" / "Medium_Phone.avd"
    if avd_dir.exists():
        for lock_file in avd_dir.glob("*.lock"):
            try:
                if lock_file.is_dir():
                    import shutil
                    shutil.rmtree(lock_file, ignore_errors=True)
                else:
                    lock_file.unlink(missing_ok=True)
                print(f"[清理] 移除了残留锁文件: {lock_file.name}")
            except Exception as e:
                print(f"[警告] 无法清理锁文件 {lock_file.name}: {e}")

def ensure_scheduled_task(bat_path: str):
    check_cmd = ["schtasks", "/query", "/tn", TASK_NAME]
    res = subprocess.run(check_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[配置] 首次注册独立交互式计划任务: {TASK_NAME}...")
        create_cmd = [
            "schtasks", "/create",
            "/tn", TASK_NAME,
            "/tr", f'"{bat_path}"',
            "/sc", "once",
            "/st", "00:00",
            "/it",
            "/f"
        ]
        create_res = subprocess.run(create_cmd, capture_output=True, text=True)
        if create_res.returncode != 0:
            raise RuntimeError(f"注册计划任务失败: {create_res.stderr}")
        print("[配置] 计划任务注册成功。")

def launch_emulator():
    print("=" * 55)
    print("  余音 (YuYin) 模拟器窗口可视化拉起工具")
    print("=" * 55)

    if is_emulator_running():
        print("[提示] 模拟器已处于运行中状态 (emulator-5554 在线)，无需重复启动。")
        return

    clean_avd_locks()

    tool_dir = Path(__file__).resolve().parent
    bat_path = tool_dir / "start_emulator.bat"
    if not bat_path.exists():
        raise FileNotFoundError(f"未找到启动批处理: {bat_path}")

    ensure_scheduled_task(str(bat_path))

    print("[启动] 正在唤醒桌面交互式模拟器窗口...")
    run_cmd = ["schtasks", "/run", "/tn", TASK_NAME]
    run_res = subprocess.run(run_cmd, capture_output=True, text=True)
    if run_res.returncode != 0:
        raise RuntimeError(f"触发启动任务失败: {run_res.stderr}")

    print("[等待] 正在等待模拟器连接并完成系统引导...")
    for sec in range(1, 35):
        time.sleep(1)
        if is_emulator_running():
            print(f"[成功] 模拟器已成功启动并就绪 (耗时约 {sec} 秒)！窗口已正常显示在您的桌面上。")
            return
        if sec % 5 == 0:
            print(f"[进度] 等待模拟器就绪中 ({sec}s)...")

    print("[提示] 启动信号已发出，若模拟器首次开机耗时较长，请稍候片刻。")

if __name__ == "__main__":
    try:
        launch_emulator()
    except Exception as err:
        print(f"[错误] {err}", file=sys.stderr)
        sys.exit(1)

