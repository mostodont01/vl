"""Compiling a VL graph into a C++ project.

generate_project() writes a self-contained CMake project into the output
folder:

    CMakeLists.txt
    cmake/                  toolchain files for cross-compiling
    runtime/vl/             the VL runtime (copied from this repo)
    nodes/<type id>/...     the code of every node type used in the graph
    generated/main.cpp      creates the nodes, sets values, connects wires

builder.py then runs CMake on it. The execution model is described in
runtime/vl/runtime.hpp.
"""

import json
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from node_catalog import NodeDef, NodePackage, is_integer_type

# Choices offered in the Compile popup: (id, label). The first one is the default.
LANGUAGES = [
    ("cpp", "C++"),
]

TARGETS = [
    ("linux-x86_64", "Linux x86-64"),
    ("linux-arm64", "Linux ARM64 (Raspberry Pi OS 64-bit, Jetson…)"),
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

RUNTIME_DIR = Path(__file__).parent / "runtime"
# Marks an output folder as written by VL, so it may be cleaned on the next build.
MARKER_FILE = ".vl-build"
IMGUI_VERSION = "v1.91.5"

# Socket/setting types every project knows, and their C++ names.
BUILTIN_CPP_TYPES = {
    "int32": "int32_t",
    "float32": "float",
    "bool": "bool",
    "string": "std::string",
}


def coerce_setting(key: str, value: Any) -> Any:
    """Validate one compile setting. Raises ValueError for unknown keys or bad values."""
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


# ---------------------------------------------------------------------------
# Graph analysis
# ---------------------------------------------------------------------------

def feedback_connections(nodes: list[dict], connections: list[dict]) -> set[int]:
    """Indices of connections that close a feedback loop.

    A depth-first walk along the wires marks every wire that leads back to a
    node still being walked (including a node feeding itself). Removing those
    wires leaves no cycles, so if they don't trigger a run, nothing can run
    forever. The walk starts from nodes without incoming wires, in a fixed
    order, so the result is the same on every compile.
    """
    outgoing: dict[str, list[tuple[int, str]]] = {n["id"]: [] for n in nodes}
    has_incoming = set()
    for i, c in enumerate(connections):
        outgoing[c["source_node"]].append((i, c["target_node"]))
        has_incoming.add(c["target_node"])

    order = sorted(outgoing, key=lambda nid: (nid in has_incoming, nid))
    state: dict[str, int] = {}  # 1 = being walked, 2 = done
    feedback: set[int] = set()

    for start in order:
        if start in state:
            continue
        # Iterative DFS: (node, iterator over its outgoing wires)
        stack = [(start, iter(outgoing[start]))]
        state[start] = 1
        while stack:
            node, wires = stack[-1]
            for index, target in wires:
                if state.get(target) == 1:
                    feedback.add(index)
                elif target not in state:
                    state[target] = 1
                    stack.append((target, iter(outgoing[target])))
                    break
            else:
                state[node] = 2
                stack.pop()
    return feedback


# ---------------------------------------------------------------------------
# Code generation
# ---------------------------------------------------------------------------

@dataclass
class GenerateResult:
    ok: bool
    messages: list[str]
    gui: bool = False


def _cpp_identifier(node_id: str) -> str:
    return "n_" + "".join(c if c.isalnum() else "_" for c in node_id)


def _cpp_string(text: str) -> str:
    # JSON string escapes (\", \\, \n, \uXXXX) are valid in C++ literals too.
    return json.dumps(text, ensure_ascii=False)


def _cpp_literal(value: Any, data_type: str, cpp_type: str) -> str:
    if data_type == "bool" or isinstance(value, bool):
        return "true" if value else "false"
    if data_type == "string" or isinstance(value, str):
        return f"std::string({_cpp_string(str(value))})"
    if is_integer_type(data_type):
        return f"{cpp_type}({int(value)})"
    return f"{cpp_type}({float(value)!r})"


def generate_project(
    graph: dict[str, Any],
    catalog: dict[str, NodeDef],
    packages: dict[str, NodePackage],
    graph_errors: list[str],
    settings: dict[str, Any],
    output_dir: Path,
    name: str,
) -> GenerateResult:
    """Validate the graph and write the C++ project. Nothing is written if invalid.

    packages has the code of every node type used (built-in and imported).
    graph_errors are the graph's own issues (e.g. unconnected inputs).
    """
    errors = list(graph_errors)
    nodes = graph["nodes"]
    connections = graph["connections"]
    used_types = sorted({n["type"] for n in nodes})

    if not nodes:
        errors.append("The graph is empty.")

    # Every used node type needs a C++ class and its code.
    for type_id in used_types:
        node_def = catalog[type_id]
        if not node_def.cpp_class:
            errors.append(f"Node type '{node_def.title}' has no \"class\" in its JSON.")
        if type_id not in packages:
            errors.append(f"The code of node type '{node_def.title}' is missing.")

    # Every socket type needs a C++ type; custom types must be defined once.
    type_owner: dict[str, str] = {}   # type name -> type id of the node whose header defines it
    for type_id in used_types:
        for type_name, type_def in catalog[type_id].types.items():
            if type_name in BUILTIN_CPP_TYPES:
                continue
            other = type_owner.get(type_name)
            if other is None:
                type_owner[type_name] = type_id
            elif type_id in packages and other in packages:
                mine = packages[type_id].files.get(type_def.header)
                theirs = packages[other].files.get(catalog[other].types[type_name].header)
                if mine != theirs or type_def.cpp != catalog[other].types[type_name].cpp:
                    errors.append(f"Type '{type_name}' is defined differently by "
                                  f"'{catalog[other].title}' and '{catalog[type_id].title}'.")

    def cpp_type(data_type: str) -> str | None:
        if data_type in BUILTIN_CPP_TYPES:
            return BUILTIN_CPP_TYPES[data_type]
        owner = type_owner.get(data_type)
        return catalog[owner].types[data_type].cpp if owner else None

    for type_id in used_types:
        node_def = catalog[type_id]
        for s in node_def.inputs + node_def.outputs + node_def.settings:
            if cpp_type(s.type) is None:
                errors.append(f"Type '{s.type}' (used by '{node_def.title}') has no C++ definition. "
                              "Declare it in a node's \"types\".")

    # Only clean folders VL wrote itself.
    if output_dir.exists() and any(output_dir.iterdir()) and not (output_dir / MARKER_FILE).exists():
        errors.append(f"The output folder {output_dir} is not empty and wasn't created by VL. "
                      "Choose an empty or new folder.")

    if errors:
        return GenerateResult(False, errors)

    gui = any(catalog[n["type"]].app_widget is not None and n.get("widget_visible", True) for n in nodes)

    # -- Write files
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
        for sub in ("runtime", "nodes", "generated", "cmake"):  # "cmake" is from older VL versions
            shutil.rmtree(output_dir / sub, ignore_errors=True)
        (output_dir / MARKER_FILE).write_text("Written by VL. This folder is regenerated on every compile.\n")
        shutil.copytree(RUNTIME_DIR, output_dir / "runtime")

        for type_id in used_types:
            # Header file -> custom type it defines, for this node.
            type_headers = {t.header: name for name, t in catalog[type_id].types.items()
                            if name not in BUILTIN_CPP_TYPES}
            for rel, content in packages[type_id].files.items():
                path = output_dir / "nodes" / type_id / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                type_name = type_headers.get(rel)
                if type_name:
                    # Several nodes may ship the same type header; a guard named
                    # after the type makes it count only once.
                    macro = "VL_TYPE_" + "".join(c if c.isalnum() else "_" for c in type_name)
                    content = (f"#ifndef {macro}\n#define {macro}\n".encode()
                               + content + f"\n#endif  // {macro}\n".encode())
                path.write_bytes(content)

        (output_dir / "generated").mkdir()
        (output_dir / "generated" / "main.cpp").write_text(
            _main_cpp(nodes, connections, catalog, cpp_type, settings, name, gui), encoding="utf-8")

        cpp_files = sorted(
            f"nodes/{type_id}/{rel}"
            for type_id in used_types
            for rel in packages[type_id].files
            if rel.endswith((".cpp", ".cc", ".cxx"))
        )
        (output_dir / "CMakeLists.txt").write_text(_cmake_lists(name, cpp_files, gui))
    except OSError as e:
        return GenerateResult(False, [f"Could not write the project to {output_dir}: {e.strerror}"])

    feedback = len(feedback_connections(nodes, connections))
    messages = [
        f"Generated C++ project in {output_dir}",
        f"{len(nodes)} nodes, {len(connections)} wires"
        + (f" ({feedback} feedback)" if feedback else "")
        + (", with app widgets" if gui else ", no window (no visible app widgets)"),
    ]
    return GenerateResult(True, messages, gui)


def _main_cpp(nodes, connections, catalog, cpp_type, settings, name, gui) -> str:
    feedback = feedback_connections(nodes, connections)
    used_types = sorted({n["type"] for n in nodes})
    connected_inputs = {(c["target_node"], c["target_socket"]) for c in connections}
    feedback_inputs = {(connections[i]["target_node"], connections[i]["target_socket"]) for i in feedback}

    out = [
        "// Generated by VL. Do not edit: this file is rewritten on every compile.",
        '#include "vl/runtime.hpp"',
        "",
    ]
    for type_id in used_types:
        for rel in catalog[type_id].code:
            if rel.endswith((".hpp", ".h", ".hh", ".hxx")):
                out.append(f'#include "nodes/{type_id}/{rel}"')
    out += [
        "",
        "int main() {",
        f"    vl::App app({_cpp_string(name)}, {'true' if settings['fullscreen'] else 'false'}, "
        f"{'true' if gui else 'false'});",
        "",
        "    // Nodes",
    ]

    for n in nodes:
        node_def = catalog[n["type"]]
        var = _cpp_identifier(n["id"])
        values = n.get("values", {})
        out.append(f"    auto& {var} = app.add<{node_def.cpp_class}>({_cpp_string(n['id'])}, "
                   f"{_cpp_string(node_def.title)});")

        for s in node_def.settings:
            if s.id in values:
                out.append(f"    {var}.{s.id} = {_cpp_literal(values[s.id], s.type, cpp_type(s.type))};")

        for s in node_def.inputs:
            out.append(f"    app.watch({var}, {var}.{s.id});")
            key = (n["id"], s.id)
            if key not in connected_inputs:
                # Unconnected input (only possible with a field): its field value.
                if s.id in values:
                    out.append(f"    {var}.{s.id}.receive({_cpp_literal(values[s.id], s.type, cpp_type(s.type))});")
            elif key in feedback_inputs:
                # Fed by a feedback wire: start from the field value (or the type's default).
                initial = (_cpp_literal(values[s.id], s.type, cpp_type(s.type)) if s.id in values
                           else f"{cpp_type(s.type)}{{}}")
                out.append(f"    {var}.{s.id}.receive({initial});  // feedback: initial value")

        if node_def.app_widget is not None:
            title_setting = node_def.app_widget.title_setting
            title = str(values.get(title_setting, "")) if title_setting else ""
            visible = n.get("widget_visible", True)
            out.append(f"    app.setWidget({var}, {'true' if visible else 'false'}, "
                       f"{_cpp_string(title or node_def.title)});")
        out.append("")

    out.append("    // Wires (feedback wires don't trigger a run)")
    for i, c in enumerate(connections):
        src, tgt = _cpp_identifier(c["source_node"]), _cpp_identifier(c["target_node"])
        triggers = "false" if i in feedback else "true"
        out.append(f"    {src}.{c['source_socket']}.connect({tgt}.{c['target_socket']}, {tgt}, {triggers});")

    out += ["", "    return app.run();", "}", ""]
    return "\n".join(out)


def _cmake_lists(name: str, cpp_files: list[str], gui: bool) -> str:
    target = "".join(c if c.isalnum() or c in "_-" else "_" for c in name) or "app"
    sources = "\n    ".join(["generated/main.cpp", "runtime/vl/app.cpp", *cpp_files])
    return f"""# Generated by VL. Do not edit: this file is rewritten on every compile.
cmake_minimum_required(VERSION 3.16)
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)  # Downloaded files get the extraction time.
endif()
project({target} CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Put the executable directly in this folder.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${{CMAKE_SOURCE_DIR}})

option(VL_GUI "Build the app widget window (Dear ImGui + SDL2)" {"ON" if gui else "OFF"})

add_executable({target}
    {sources}
)
target_include_directories({target} PRIVATE ${{CMAKE_SOURCE_DIR}} ${{CMAKE_SOURCE_DIR}}/runtime)

if(VL_GUI)
    include(FetchContent)
    if(CMAKE_CROSSCOMPILING)
        include(runtime/cmake/sdl2-from-source.cmake)
    else()
        find_package(SDL2 REQUIRED)
    endif()
    FetchContent_Declare(imgui
        URL https://github.com/ocornut/imgui/archive/refs/tags/{IMGUI_VERSION}.tar.gz)
    FetchContent_MakeAvailable(imgui)

    target_sources({target} PRIVATE
        ${{imgui_SOURCE_DIR}}/imgui.cpp
        ${{imgui_SOURCE_DIR}}/imgui_draw.cpp
        ${{imgui_SOURCE_DIR}}/imgui_tables.cpp
        ${{imgui_SOURCE_DIR}}/imgui_widgets.cpp
        ${{imgui_SOURCE_DIR}}/backends/imgui_impl_sdl2.cpp
        ${{imgui_SOURCE_DIR}}/backends/imgui_impl_sdlrenderer2.cpp)
    target_include_directories({target} PRIVATE ${{imgui_SOURCE_DIR}} ${{imgui_SOURCE_DIR}}/backends)
    target_compile_definitions({target} PRIVATE VL_GUI)
    if(TARGET SDL2::SDL2main)
        target_link_libraries({target} PRIVATE SDL2::SDL2main)
    endif()
    if(TARGET SDL2::SDL2)
        target_link_libraries({target} PRIVATE SDL2::SDL2)
    else()
        target_link_libraries({target} PRIVATE SDL2::SDL2-static)
    endif()
endif()
"""


TOOLCHAIN_FILES = {
    "linux-arm64": "runtime/cmake/aarch64-zig.cmake",
    "windows-x86_64": "runtime/cmake/mingw-w64-x86_64.cmake",
}
