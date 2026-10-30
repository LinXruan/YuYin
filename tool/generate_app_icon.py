"""生成 Android 启动图标：Material Icons 的 music_note 音符。

用法（必须使用项目约定的 deepseek 环境 Python）：
    D:\\Install\\anaconda3\\envs\\deepseek\\python.exe tool\\generate_app_icon.py
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RES_DIR = ROOT / "android" / "app" / "src" / "main" / "res"
DEFAULT_FONT = Path(
    r"C:\dev\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf"
)

# Material Icons: music_note (0xe415)
GLYPH = "\ue415"
BACKGROUND = (255, 216, 228, 255)  # #FFD8E4
FOREGROUND = (62, 0, 29, 255)  # #3E001D

LAUNCHER_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
# 自适应图标前景：108dp 画布，音符取小一些，避免被系统遮罩后显得过大
FOREGROUND_SIZES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}
# 启动页 logo：120dp 浅粉圆底 + 音符
LAUNCH_LOGO_SIZES = {
    "mdpi": 120,
    "hdpi": 180,
    "xhdpi": 240,
    "xxhdpi": 360,
    "xxxhdpi": 480,
}


def draw_note(
    draw: ImageDraw.ImageDraw,
    font_path: Path,
    canvas: int,
    font_ratio: float,
) -> None:
    font = ImageFont.truetype(str(font_path), int(canvas * font_ratio))
    left, top, right, bottom = draw.textbbox((0, 0), GLYPH, font=font)
    x = (canvas - (right - left)) / 2 - left
    y = (canvas - (bottom - top)) / 2 - top
    draw.text((x, y), GLYPH, font=font, fill=FOREGROUND)


def render_icon(font_path: Path, shape: str, font_ratio: float = 0.62) -> Image.Image:
    """渲染浅粉背景 + 音符的图标（shape=square/round）。"""
    size = 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    if shape == "round":
        draw.ellipse((0, 0, size - 1, size - 1), fill=BACKGROUND)
    else:
        draw.rectangle((0, 0, size - 1, size - 1), fill=BACKGROUND)
    draw_note(draw, font_path, size, font_ratio)
    return canvas


def render_foreground(font_path: Path) -> Image.Image:
    """自适应图标前景：透明背景 + 居中音符。"""
    size = 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    # 0.50 的字号让音符在 72dp 可见区域内约占 55%
    draw_note(draw, font_path, size, 0.50)
    return canvas


def save_scaled(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate YuYin launcher icons")
    parser.add_argument("--font", type=Path, default=DEFAULT_FONT)
    args = parser.parse_args()

    if not args.font.exists():
        raise SystemExit(f"MaterialIcons font not found: {args.font}")

    square = render_icon(args.font, "square")
    round_icon = render_icon(args.font, "round")
    foreground = render_foreground(args.font)

    for density, size in LAUNCHER_SIZES.items():
        save_scaled(square, RES_DIR / f"mipmap-{density}" / "ic_launcher.png", size)
        save_scaled(
            round_icon,
            RES_DIR / f"mipmap-{density}" / "ic_launcher_round.png",
            size,
        )
        print(f"launcher {density}: {size}x{size}")

    for density, size in FOREGROUND_SIZES.items():
        save_scaled(
            foreground,
            RES_DIR / f"mipmap-{density}" / "ic_launcher_foreground.png",
            size,
        )
        print(f"foreground {density}: {size}x{size}")

    for density, size in LAUNCH_LOGO_SIZES.items():
        save_scaled(
            round_icon,
            RES_DIR / f"drawable-{density}" / "launch_logo.png",
            size,
        )
        print(f"launch logo {density}: {size}x{size}")


if __name__ == "__main__":
    main()
