"""生成 Android 启动图标：Material Icons 的 music_note 音符。

用法（必须使用项目约定的 deepseek 环境 Python）：
    D:\Install\anaconda3\envs\deepseek\python.exe tool\generate_app_icon.py
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


def draw_note(
    draw: ImageDraw.ImageDraw,
    font_path: Path,
    canvas: int,
    font_ratio: float,
    y_shift_ratio: float = 0.04,  # 将音符往正下方适度微调，弥补竖向长音符杆带来的视觉重心偏上问题
) -> None:
    font = ImageFont.truetype(str(font_path), int(canvas * font_ratio))
    left, top, right, bottom = draw.textbbox((0, 0), GLYPH, font=font)
    x = (canvas - (right - left)) / 2 - left
    y = (canvas - (bottom - top)) / 2 - top + (canvas * y_shift_ratio)
    draw.text((x, y), GLYPH, font=font, fill=FOREGROUND)


def render_foreground(font_path: Path) -> Image.Image:
    """自适应图标前景：透明背景 + 居中偏下微调音符。"""
    size = 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    # 0.50 的字号让音符在 72dp 可见区域内约占 55%
    draw_note(draw, font_path, size, 0.50)
    return canvas


def render_round_icon_from_adaptive(foreground: Image.Image) -> Image.Image:
    """从 108dp 自适应图标直接裁剪出 72dp 可视圆形，保证圆形图标与桌面完全一致。"""
    size = foreground.width
    # 72dp / 108dp 的比例
    circle_diameter = int(size * (72.0 / 108.0))
    offset = (size - circle_diameter) // 2

    bg = Image.new("RGBA", (size, size), BACKGROUND)
    composite = Image.alpha_composite(bg, foreground)

    mask = Image.new("L", (circle_diameter, circle_diameter), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.ellipse((0, 0, circle_diameter - 1, circle_diameter - 1), fill=255)

    cropped = composite.crop((offset, offset, offset + circle_diameter, offset + circle_diameter))
    round_icon = Image.new("RGBA", (circle_diameter, circle_diameter), (0, 0, 0, 0))
    round_icon.paste(cropped, (0, 0), mask)
    return round_icon


def render_square_icon(foreground: Image.Image) -> Image.Image:
    """渲染浅粉方形背景 + 音符的图标（裁切 central 72dp 区域，与圆角图标音符比例严格一致）。"""
    size = foreground.width
    crop_size = int(size * (72.0 / 108.0))
    offset = (size - crop_size) // 2

    bg = Image.new("RGBA", (size, size), BACKGROUND)
    composite = Image.alpha_composite(bg, foreground)
    return composite.crop((offset, offset, offset + crop_size, offset + crop_size))


def save_scaled(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate YuYin launcher icons")
    parser.add_argument("--font", type=Path, default=DEFAULT_FONT)
    args = parser.parse_args()

    if not args.font.exists():
        raise SystemExit(f"MaterialIcons font not found: {args.font}")

    foreground = render_foreground(args.font)
    round_icon = render_round_icon_from_adaptive(foreground)
    square_icon = render_square_icon(foreground)

    for density, size in LAUNCHER_SIZES.items():
        save_scaled(square_icon, RES_DIR / f"mipmap-{density}" / "ic_launcher.png", size)
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


if __name__ == "__main__":
    main()
