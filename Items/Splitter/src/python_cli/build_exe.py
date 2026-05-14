"""Build the Lee Stem Splitter CLI (PyInstaller one-dir).

部署到其它电脑：在本机成功执行本脚本后，将整个 Items/Splitter 目录（含 bin/LeeStemSplitterCLI/）
覆盖到目标机的 REAPER Scripts 下对应路径即可。

依赖：
  pip install pyinstaller soundfile numpy scipy scikit-learn librosa ...
  以及 SONICCOMPASS_ROOT 环境变量指向含 core/stem_splitter/engine.py 的 SonicCompass 仓库；
  若未设置，默认使用 Windows 路径 E:\\Audio_Projects\\Tools\\SonicCompass（可按 --source-root 覆盖）。

示例：
  python build_exe.py
  python build_exe.py --source-root D:\\repos\\SonicCompass --clean
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Sequence


DEFAULT_SOURCE_ROOT = Path(os.environ.get("SONICCOMPASS_ROOT", r"E:\Audio_Projects\Tools\SonicCompass"))
EXE_NAME = "LeeStemSplitterCLI"


def _data_separator() -> str:
    return ";" if os.name == "nt" else ":"


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the StemSplitterEngine CLI into a fast-starting one-directory executable."
    )
    parser.add_argument(
        "--source-root",
        default=str(DEFAULT_SOURCE_ROOT),
        help="SonicCompass project root containing core/stem_splitter/engine.py.",
    )
    parser.add_argument(
        "--name",
        default=EXE_NAME,
        help="Executable name without extension.",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Pass --clean to PyInstaller.",
    )
    return parser.parse_args(argv)


def build_command(args: argparse.Namespace) -> list[str]:
    script_path = Path(__file__).resolve().parent / "cli_main.py"
    splitter_root = Path(__file__).resolve().parents[2]
    bin_dir = splitter_root / "bin"
    build_dir = splitter_root / "build" / "pyinstaller"
    work_dir = build_dir / f"work-{os.getpid()}"
    source_root = Path(args.source_root).resolve()
    engine_path = source_root / "core" / "stem_splitter" / "engine.py"

    if not script_path.is_file():
        raise FileNotFoundError(f"CLI entry not found: {script_path}")
    if not engine_path.is_file():
        raise FileNotFoundError(f"StemSplitterEngine not found: {engine_path}")

    bin_dir.mkdir(parents=True, exist_ok=True)
    build_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--onedir",
        "--noconfirm",
        "--console",
        "--name",
        str(args.name),
        "--distpath",
        str(bin_dir),
        "--workpath",
        str(work_dir),
        "--specpath",
        str(build_dir),
        "--hidden-import",
        "librosa",
        "--hidden-import",
        "librosa.decompose",
        "--hidden-import",
        "norbert",
        "--collect-all",
        "soundfile",
        "--exclude-module",
        "PySide6",
        "--exclude-module",
        "PyQt6",
        "--exclude-module",
        "matplotlib",
        "--exclude-module",
        "tkinter",
        "--exclude-module",
        "IPython",
        "--exclude-module",
        "jupyter",
        "--exclude-module",
        "scipy.spatial",
        "--exclude-module",
        "scipy.interpolate",
        "--exclude-module",
        "pandas",
        "--exclude-module",
        "torch",
        "--exclude-module",
        "transformers",
        "--add-data",
        f"{engine_path}{_data_separator()}core/stem_splitter",
        str(script_path),
    ]

    norbert_root = source_root / "REF" / "Audio" / "norbert-master"
    if norbert_root.is_dir():
        cmd.extend(["--paths", str(norbert_root)])
        cmd.extend([
            "--add-data",
            f"{norbert_root}{_data_separator()}REF/Audio/norbert-master",
        ])

    if args.clean:
        cmd.insert(4, "--clean")

    return cmd


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    cmd = build_command(args)
    print("Running:")
    print(" ".join(f'"{part}"' if " " in part else part for part in cmd))
    completed = subprocess.run(cmd, check=False)
    return int(completed.returncode)


if __name__ == "__main__":
    raise SystemExit(main())
