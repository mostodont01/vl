"""Runs CMake on a generated project in the background and collects the log.

The UI shows `log` and `status` while the build runs. If the tools needed
for the chosen target are missing, nothing is run: the log says what to
install, and the generated project stays in the output folder.
"""

import importlib.util
import platform
import shutil
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, QProcessEnvironment, QUrl, Property, Signal, Slot

import compiler

# Debian/Ubuntu packages for each missing tool, used in the install hint.
_PACKAGES = {
    "cmake": "cmake",
    "make": "build-essential",
    "c++": "build-essential",
    "x86_64-w64-mingw32-g++": "g++-mingw-w64-x86-64",
    "sdl2": "libsdl2-dev",
}


def _host_target() -> str:
    machine = platform.machine().lower()
    if platform.system() == "Linux":
        return "linux-arm64" if machine in ("aarch64", "arm64") else "linux-x86_64"
    if platform.system() == "Windows":
        return "windows-x86_64"
    return ""


def _zig() -> str:
    """Path of the Zig compiler from the `ziglang` Python package, or ""."""
    spec = importlib.util.find_spec("ziglang")
    if spec is None or spec.origin is None:
        return ""
    zig = Path(spec.origin).parent / ("zig.exe" if sys.platform == "win32" else "zig")
    return str(zig) if zig.exists() else ""


def _has_native_sdl2() -> bool:
    return bool(shutil.which("sdl2-config")) or Path("/usr/include/SDL2/SDL.h").exists()


def missing_tools(target: str, gui: bool) -> list[str]:
    """Tools (keys of _PACKAGES) needed for this target that aren't installed."""
    missing = []
    if not shutil.which("cmake"):
        missing.append("cmake")
    if not (shutil.which("ninja") or shutil.which("make")):
        missing.append("make")

    native = target == _host_target()
    if native:
        if not (shutil.which("c++") or shutil.which("g++") or shutil.which("clang++")):
            missing.append("c++")
        if gui and not _has_native_sdl2():
            missing.append("sdl2")
    elif target == "linux-arm64":
        # Zig cross-compiles; SDL2 is built from source with this machine's headers.
        if not _zig():
            missing.append("zig")
        if gui and not (_has_native_sdl2() and shutil.which("wayland-scanner")):
            missing.append("sdl2")
    elif target == "windows-x86_64" and not shutil.which("x86_64-w64-mingw32-g++"):
        missing.append("x86_64-w64-mingw32-g++")
    return missing


class Builder(QObject):
    logChanged = Signal()
    statusChanged = Signal()
    # Emitted when a build ends: (success, short summary).
    finished = Signal(bool, str)

    def __init__(self):
        super().__init__()
        self._log: list[str] = []
        self._status = "idle"   # idle, running, succeeded, failed, generated
        self._output_dir = ""
        self._executable = ""
        self._process: QProcess | None = None
        self._steps: list[list[str]] = []
        self._environment = QProcessEnvironment.systemEnvironment()

    # -- Properties ---------------------------------------------------------

    @Property(str, notify=logChanged)
    def log(self) -> str:
        return "\n".join(self._log)

    @Property(str, notify=statusChanged)
    def status(self) -> str:
        return self._status

    @Property(bool, notify=statusChanged)
    def running(self) -> bool:
        return self._status == "running"

    @Property(str, notify=statusChanged)
    def outputFolderUrl(self) -> str:
        return QUrl.fromLocalFile(self._output_dir).toString() if self._output_dir else ""

    @Property(str, notify=statusChanged)
    def executable(self) -> str:
        return self._executable

    # -- Used by Project ----------------------------------------------------

    def begin(self):
        """Start a new log for a compile."""
        self.cancel()
        self._log = []
        self._output_dir = ""
        self._executable = ""
        self._set_status("running")
        self.logChanged.emit()

    def append(self, line: str):
        self._log.append(line)
        self.logChanged.emit()

    def fail(self, summary: str):
        self.append("")
        self.append(f"✕ {summary}")
        self._set_status("failed")
        self.finished.emit(False, summary)

    def build(self, output_dir: Path, settings: dict, name: str, gui: bool):
        """Configure and build the generated project with CMake (asynchronously)."""
        self._output_dir = str(output_dir)
        target = settings["target"]

        missing = missing_tools(target, gui)
        if missing:
            packages = " ".join(sorted({_PACKAGES[m] for m in missing if m in _PACKAGES}))
            self.append("")
            self.append("The C++ project was generated, but it can't be built here yet. Missing: "
                        + ", ".join(missing))
            if packages:
                self.append(f"Install them with:  sudo apt install {packages}")
            if "zig" in missing:
                self.append(f"Install Zig (the cross-compiler) with:  {sys.executable} -m pip install ziglang")
            self.append(f"Or build the project in {output_dir} on the target machine with CMake.")
            self._set_status("generated")
            self.finished.emit(False, "Project generated, not built (missing tools)")
            return

        # One build folder per target: CMake can't switch compilers in place.
        build_dir = output_dir / "build" / target
        configure = ["cmake", "-S", str(output_dir), "-B", str(build_dir),
                     f"-DCMAKE_BUILD_TYPE={'Release' if settings['build_type'] == 'release' else 'Debug'}"]
        if shutil.which("ninja") and not (build_dir / "Makefile").exists():
            configure += ["-G", "Ninja"]
        if target in compiler.TOOLCHAIN_FILES and target != _host_target():
            configure.append(f"-DCMAKE_TOOLCHAIN_FILE={output_dir / compiler.TOOLCHAIN_FILES[target]}")
        self._steps = [configure, ["cmake", "--build", str(build_dir), "--parallel"]]
        self._environment = QProcessEnvironment.systemEnvironment()
        if _zig():
            self._environment.insert("VL_ZIG", _zig())
        self._executable = str(output_dir / compiler.executable_file_name(name, target))
        self._run_next_step()

    @Slot()
    def cancel(self):
        if self._process is not None:
            self._steps = []
            process, self._process = self._process, None
            process.kill()
            process.waitForFinished(2000)
            self.append("")
            self.append("✕ Build cancelled.")
            self._set_status("failed")
            self.finished.emit(False, "Build cancelled")

    # -- Internals ----------------------------------------------------------

    def _set_status(self, status: str):
        if status != self._status:
            self._status = status
            self.statusChanged.emit()

    def _run_next_step(self):
        if not self._steps:
            self.append("")
            self.append(f"✓ Built {self._executable}")
            self._set_status("succeeded")
            self.finished.emit(True, f"Built {Path(self._executable).name}")
            return

        command = self._steps.pop(0)
        self.append("")
        self.append("$ " + " ".join(command))
        process = QProcess(self)
        process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        process.setProcessEnvironment(self._environment)
        process.readyReadStandardOutput.connect(lambda: self._read_output(process))
        process.finished.connect(lambda code, exit_status: self._step_finished(process, code, exit_status))
        process.errorOccurred.connect(lambda error: self._step_error(process, error))
        self._process = process
        process.start(command[0], command[1:])

    def _read_output(self, process: QProcess):
        text = bytes(process.readAllStandardOutput()).decode("utf-8", errors="replace")
        for line in text.splitlines():
            self._log.append(line)
        self.logChanged.emit()

    def _step_finished(self, process: QProcess, code: int, exit_status):
        if process is not self._process:
            return  # Cancelled.
        self._read_output(process)
        self._process = None
        if exit_status != QProcess.ExitStatus.NormalExit or code != 0:
            self.fail(f"Build failed (exit code {code}). See the log above.")
        else:
            self._run_next_step()

    def _step_error(self, process: QProcess, error):
        if process is not self._process or error != QProcess.ProcessError.FailedToStart:
            return
        self._process = None
        self.fail(f"Could not start {process.program()}.")
