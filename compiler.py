"""Compiling a VL graph into an executable.

Only the settings and the entry point exist so far; code generation comes
later. compile_project() is what the Compile popup ends up calling.
"""

from pathlib import Path
from typing import Any

# Choices offered in the Compile popup: (id, label). The first one is the default.
LANGUAGES = [
    ("cpp", "C++"),
]

TARGETS = [
    ("linux-x86_64", "Linux x86-64"),
    ("linux-arm64", "Linux ARM64 (Raspberry Pi, Jetson…)"),
    ("windows-x86_64", "Windows x86-64 (.exe)"),
]

BUILD_TYPES = [
    ("release", "Release (optimized)"),
    ("debug", "Debug (debug symbols, no optimization)"),
]

DEFAULT_SETTINGS: dict[str, Any] = {
    "language": LANGUAGES[0][0],
    "target": TARGETS[0][0],
    "build_type": BUILD_TYPES[0][0],
    "output_dir": "",        # "" = <project folder>/build
    "executable_name": "",   # "" = project name
    "fullscreen": True,
}

_CHOICES = {
    "language": {i for i, _ in LANGUAGES},
    "target": {i for i, _ in TARGETS},
    "build_type": {i for i, _ in BUILD_TYPES},
}


def coerce_setting(key: str, value: Any) -> Any:
    """Validate one setting. Raises ValueError for unknown keys or bad values."""
    if key not in DEFAULT_SETTINGS:
        raise ValueError(f"unknown compile setting {key!r}")
    if key in _CHOICES:
        if value not in _CHOICES[key]:
            raise ValueError(f"invalid {key}: {value!r}")
        return value
    if key == "fullscreen":
        if not isinstance(value, bool):
            raise ValueError("fullscreen must be true or false")
        return value
    return str(value).strip()


def load_settings(raw: Any) -> dict[str, Any]:
    """Settings from a project file, falling back to defaults for anything invalid."""
    settings = dict(DEFAULT_SETTINGS)
    if isinstance(raw, dict):
        for key, value in raw.items():
            try:
                settings[key] = coerce_setting(key, value)
            except ValueError:
                pass
    return settings


def executable_file_name(name: str, target: str) -> str:
    return name + ".exe" if target.startswith("windows") else name


def compile_project(graph: dict[str, Any], settings: dict[str, Any], output_dir: Path, name: str) -> bool:
    """Compile the graph. Not implemented yet: only reports what it would do."""
    exe = output_dir / executable_file_name(name, settings["target"])
    print("[VL] Compile requested")
    print(f"     language:   {settings['language']}")
    print(f"     target:     {settings['target']}")
    print(f"     build type: {settings['build_type']}")
    print(f"     fullscreen: {settings['fullscreen']}")
    print(f"     output:     {exe}")
    print(f"     graph:      {len(graph['nodes'])} nodes, {len(graph['connections'])} connections")
    print("[VL] No compiler yet; nothing was built.")
    return True
