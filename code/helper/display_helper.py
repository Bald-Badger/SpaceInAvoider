"""Pygame display helpers for the SpaceAvoider toy avionics display."""

from __future__ import annotations

import argparse
import os
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CircleDemoConfig:
    width: int = 800
    height: int = 480
    fullscreen: bool = True
    seconds: float = 5.0
    video_driver: str = "auto"
    backend: str = "auto"
    framebuffer: Path = Path("/dev/fb0")
    framebuffer_sysfs: Path = Path("/sys/class/graphics/fb0")
    background_color: tuple[int, int, int] = (0, 0, 0)
    circle_color: tuple[int, int, int] = (0, 220, 120)
    circle_radius: int = 80


def draw_circle_demo(config: CircleDemoConfig | None = None) -> None:
    """Draw a centered circle that changes color once per second."""

    config = config or CircleDemoConfig()
    pygame = _import_pygame()

    if config.backend == "fb0":
        _draw_circle_to_framebuffer(pygame, config)
        return

    _configure_sdl_environment(config)
    pygame.init()
    try:
        try:
            screen = _open_display(pygame, config)
        except SystemExit:
            if config.backend != "auto":
                raise

            pygame.quit()
            print("falling back to pygame Surface -> /dev/fb0")
            _draw_circle_to_framebuffer(pygame, config)
            return

        pygame.display.set_caption("SpaceAvoider Display Test")

        width, height = screen.get_size()
        print(
            "pygame display:",
            f"driver={pygame.display.get_driver()}",
            f"size={width}x{height}",
            f"fullscreen={config.fullscreen}",
        )

        clock = pygame.time.Clock()
        start = time.monotonic()
        deadline = time.monotonic() + config.seconds
        running = True

        while running and time.monotonic() < deadline:
            now = time.monotonic()
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN and event.key in (pygame.K_ESCAPE, pygame.K_q):
                    running = False

            _draw_circle_on_surface(pygame, screen, config, int(now - start))
            pygame.display.flip()
            clock.tick(30)
    finally:
        pygame.quit()


def _draw_circle_to_framebuffer(pygame, config: CircleDemoConfig) -> None:
    info = _read_framebuffer_info(config.framebuffer_sysfs)
    patches = _build_circle_patches(pygame, config, info)
    print(
        "framebuffer display:",
        f"device={config.framebuffer}",
        f"size={info.width}x{info.height}",
        f"bpp={info.bits_per_pixel}",
        f"stride={info.stride}",
    )

    steps = max(1, int(config.seconds))
    start = time.monotonic()
    with config.framebuffer.open("r+b", buffering=0) as framebuffer:
        _clear_framebuffer(framebuffer, config, info)
        for step in range(steps):
            _write_framebuffer_patch(framebuffer, patches[step % len(patches)], info)
            next_frame_at = start + step + 1
            time.sleep(max(0.0, next_frame_at - time.monotonic()))


@dataclass(frozen=True)
class FramebufferInfo:
    width: int
    height: int
    bits_per_pixel: int
    stride: int

    @property
    def bytes_per_pixel(self) -> int:
        return self.bits_per_pixel // 8

    @property
    def line_bytes(self) -> int:
        return self.width * self.bytes_per_pixel

    @property
    def buffer_bytes(self) -> int:
        return self.height * self.stride


@dataclass(frozen=True)
class FramebufferPatch:
    x: int
    y: int
    width: int
    height: int
    payload: bytes | bytearray

    @property
    def payload_line_bytes(self) -> int:
        return self.width * 4

    @property
    def right(self) -> int:
        return self.x + self.width

    @property
    def bottom(self) -> int:
        return self.y + self.height


def _build_circle_patches(
    pygame, config: CircleDemoConfig, info: FramebufferInfo
) -> list[FramebufferPatch]:
    radius = _circle_radius(info.width, info.height, config)
    diameter = radius * 2 + 1
    center_x, center_y = _circle_center(info.width, info.height)
    patch_info = FramebufferInfo(
        width=diameter,
        height=diameter,
        bits_per_pixel=info.bits_per_pixel,
        stride=diameter * info.bytes_per_pixel,
    )
    surface = pygame.Surface((diameter, diameter))
    patches: list[FramebufferPatch] = []

    for color in _circle_colors(config):
        surface.fill(config.background_color)
        pygame.draw.circle(surface, color, (radius, radius), radius)
        patches.append(
            FramebufferPatch(
                x=center_x - radius,
                y=center_y - radius,
                width=diameter,
                height=diameter,
                payload=_surface_to_framebuffer_payload(pygame, surface, patch_info),
            )
        )

    return patches


def _read_text(path: Path) -> str:
    return path.read_text(encoding="ascii").strip()


def _read_framebuffer_info(sysfs_dir: Path) -> FramebufferInfo:
    width_text, height_text = _read_text(sysfs_dir / "virtual_size").split(",", 1)
    bits_per_pixel = int(_read_text(sysfs_dir / "bits_per_pixel"))
    stride = int(_read_text(sysfs_dir / "stride"))
    info = FramebufferInfo(
        width=int(width_text),
        height=int(height_text),
        bits_per_pixel=bits_per_pixel,
        stride=stride,
    )

    if info.bits_per_pixel != 32:
        raise SystemExit(f"Expected a 32-bit framebuffer, got {info.bits_per_pixel} bpp")
    if info.stride < info.line_bytes:
        raise SystemExit(f"Framebuffer stride {info.stride} is smaller than {info.line_bytes}")

    return info


def _draw_circle_on_surface(pygame, surface, config: CircleDemoConfig, step: int) -> None:
    width, height = surface.get_size()
    surface.fill(config.background_color)
    center = _circle_center(width, height)
    radius = _circle_radius(width, height, config)
    pygame.draw.circle(surface, _circle_color_for_step(config, step), center, radius)


def _circle_center(width: int, height: int) -> tuple[int, int]:
    return width // 2, height // 2


def _circle_radius(width: int, height: int, config: CircleDemoConfig) -> int:
    return min(config.circle_radius, max(10, min(width, height) // 3))


def _circle_color_for_step(config: CircleDemoConfig, step: int) -> tuple[int, int, int]:
    colors = _circle_colors(config)
    return colors[step % len(colors)]


def _circle_colors(config: CircleDemoConfig) -> tuple[tuple[int, int, int], ...]:
    return (
        config.circle_color,
        (255, 230, 70),
        (255, 90, 90),
        (80, 170, 255),
        (210, 120, 255),
    )


def _surface_to_framebuffer_payload(pygame, surface, info: FramebufferInfo) -> bytes | bytearray:
    try:
        pixel_bytes = pygame.image.tostring(surface, "BGRA")
    except ValueError:
        pixel_bytes = _rgba_to_bgra(pygame.image.tostring(surface, "RGBA"))

    if info.stride == info.line_bytes:
        return pixel_bytes

    payload = bytearray(info.buffer_bytes)
    source = memoryview(pixel_bytes)
    target = memoryview(payload)

    for y in range(info.height):
        source_start = y * info.line_bytes
        target_start = y * info.stride
        target[target_start : target_start + info.line_bytes] = source[
            source_start : source_start + info.line_bytes
        ]

    return payload


def _rgba_to_bgra(rgba_bytes: bytes) -> bytes:
    bgra = bytearray(len(rgba_bytes))
    for index in range(0, len(rgba_bytes), 4):
        bgra[index] = rgba_bytes[index + 2]
        bgra[index + 1] = rgba_bytes[index + 1]
        bgra[index + 2] = rgba_bytes[index]
        bgra[index + 3] = rgba_bytes[index + 3]
    return bytes(bgra)


def _clear_framebuffer(framebuffer, config: CircleDemoConfig, info: FramebufferInfo) -> None:
    framebuffer.seek(0)
    framebuffer.write(_solid_framebuffer_payload(config.background_color, info))


def _solid_framebuffer_payload(
    color: tuple[int, int, int], info: FramebufferInfo
) -> bytes | bytearray:
    red, green, blue = color
    pixel = bytes((blue, green, red, 255))
    line = pixel * info.width

    if info.stride == info.line_bytes:
        return line * info.height

    payload = bytearray(info.buffer_bytes)
    target = memoryview(payload)
    for y in range(info.height):
        start = y * info.stride
        target[start : start + info.line_bytes] = line
    return payload


def _write_framebuffer_patch(framebuffer, patch: FramebufferPatch, info: FramebufferInfo) -> None:
    if patch.x < 0 or patch.y < 0 or patch.right > info.width or patch.bottom > info.height:
        raise SystemExit("Framebuffer patch is outside the visible framebuffer")

    source = memoryview(patch.payload)
    for row in range(patch.height):
        source_start = row * patch.payload_line_bytes
        target_start = (patch.y + row) * info.stride + patch.x * info.bytes_per_pixel
        framebuffer.seek(target_start)
        framebuffer.write(source[source_start : source_start + patch.payload_line_bytes])


def _configure_sdl_environment(config: CircleDemoConfig) -> None:
    os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
    os.environ.setdefault("SDL_VIDEO_CENTERED", "1")

    if config.video_driver != "auto":
        os.environ["SDL_VIDEODRIVER"] = config.video_driver
        return

    if not _has_desktop_display():
        os.environ.setdefault("SDL_VIDEODRIVER", "kmsdrm")


def _has_desktop_display() -> bool:
    return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def _open_display(pygame, config: CircleDemoConfig):
    flags = pygame.FULLSCREEN if config.fullscreen else 0
    size = (0, 0) if config.fullscreen else (config.width, config.height)

    try:
        return pygame.display.set_mode(size, flags)
    except pygame.error as first_error:
        current_driver = os.environ.get("SDL_VIDEODRIVER", "")
        if current_driver != "kmsdrm":
            raise

        print(f"kmsdrm display open failed: {first_error}")
        print("trying SDL_VIDEODRIVER=linuxfb fallback")
        pygame.display.quit()
        os.environ["SDL_VIDEODRIVER"] = "linuxfb"
        try:
            pygame.display.init()
            return pygame.display.set_mode(size, flags)
        except pygame.error as second_error:
            raise SystemExit(
                "No visible pygame console video driver is available. "
                "The helper can still draw via /dev/fb0 with --backend fb0."
            ) from second_error


def _import_pygame():
    os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")

    try:
        import pygame
    except ModuleNotFoundError as exc:
        raise SystemExit(
            "pygame is not installed. Run setup, activate the venv, then try again:\n"
            "  sudo bash scripts/setup_pi_overlay.sh\n"
            "  source .venv/bin/activate"
        ) from exc

    return pygame


def _parse_color(text: str) -> tuple[int, int, int]:
    parts = text.split(",")
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("color must be R,G,B")

    try:
        red, green, blue = (int(part) for part in parts)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("color values must be integers") from exc

    for value in (red, green, blue):
        if not 0 <= value <= 255:
            raise argparse.ArgumentTypeError("color values must be between 0 and 255")

    return red, green, blue


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Draw a simple pygame circle demo.")
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--windowed", action="store_true", help="use a window instead of fullscreen")
    parser.add_argument("--seconds", type=float, default=5.0)
    parser.add_argument("--radius", type=int, default=80)
    parser.add_argument(
        "--backend",
        choices=("auto", "pygame", "fb0"),
        default="auto",
        help="draw through SDL display or render with pygame then write /dev/fb0",
    )
    parser.add_argument(
        "--video-driver",
        choices=("auto", "kmsdrm", "linuxfb", "x11", "wayland"),
        default="auto",
        help="SDL video driver to request; auto uses kmsdrm when no desktop display exists",
    )
    parser.add_argument("--background", type=_parse_color, default=(0, 0, 0), metavar="R,G,B")
    parser.add_argument("--color", type=_parse_color, default=(0, 220, 120), metavar="R,G,B")
    parser.add_argument("--framebuffer", type=Path, default=Path("/dev/fb0"))
    parser.add_argument("--framebuffer-sysfs", type=Path, default=Path("/sys/class/graphics/fb0"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    draw_circle_demo(
        CircleDemoConfig(
            width=args.width,
            height=args.height,
            fullscreen=not args.windowed,
            seconds=args.seconds,
            video_driver=args.video_driver,
            backend=args.backend,
            framebuffer=args.framebuffer,
            framebuffer_sysfs=args.framebuffer_sysfs,
            background_color=args.background,
            circle_color=args.color,
            circle_radius=args.radius,
        )
    )


if __name__ == "__main__":
    main()
