from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
import traceback
from pathlib import Path
from typing import Sequence

import soundfile as sf


STEM_SUFFIXES = {
    "tonal": "_Tonal.wav",
    "transient": "_Transient.wav",
    "noise": "_Noise.wav",
}


def _candidate_source_roots() -> list[Path]:
    roots: list[Path] = []
    env_root = os.environ.get("SONICCOMPASS_ROOT")
    if env_root:
        roots.append(Path(env_root))

    # Development fallback for the current integration workspace. Frozen builds
    # should already contain the imported modules via PyInstaller.
    roots.append(Path(r"E:\Audio_Projects\Tools\SonicCompass"))
    return roots


def _prepare_import_path() -> None:
    for root in _candidate_source_roots():
        if (root / "core" / "stem_splitter" / "engine.py").is_file():
            root_str = str(root)
            if root_str not in sys.path:
                sys.path.insert(0, root_str)
            return


def _engine_path() -> Path:
    if getattr(sys, "frozen", False):
        bundled_root = Path(getattr(sys, "_MEIPASS"))
        bundled_engine = bundled_root / "core" / "stem_splitter" / "engine.py"
        if bundled_engine.is_file():
            return bundled_engine

    for root in _candidate_source_roots():
        engine_path = root / "core" / "stem_splitter" / "engine.py"
        if engine_path.is_file():
            return engine_path

    raise FileNotFoundError("Unable to locate StemSplitterEngine engine.py.")


def _load_stem_splitter_engine():
    engine_path = _engine_path()
    spec = importlib.util.spec_from_file_location("lee_splitter_engine", engine_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Unable to load StemSplitterEngine from: {engine_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module.StemSplitterEngine

def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run SonicCompass StemSplitterEngine as a REAPER-friendly CLI."
    )
    parser.add_argument("--input", required=True, help="Input audio file path.")
    parser.add_argument("--margin", type=float, required=True, help="HPSS margin, 1.0-10.0.")
    parser.add_argument("--wiener", type=int, required=True, help="Norbert EM iterations, 0-10.")
    parser.add_argument(
        "--hop",
        type=int,
        required=True,
        choices=(256, 512, 1024, 2048),
        help="STFT hop length.",
    )
    parser.add_argument("--outdir", required=True, help="Output directory for generated stems.")
    return parser.parse_args(argv)


def _output_paths(input_path: Path, outdir: Path) -> dict[str, Path]:
    base = input_path.stem
    return {
        name: outdir / f"{base}{suffix}"
        for name, suffix in STEM_SUFFIXES.items()
    }


def run(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    input_path = Path(args.input).expanduser().resolve()
    outdir = Path(args.outdir).expanduser().resolve()

    if not input_path.is_file():
        raise FileNotFoundError(f"Input file does not exist: {input_path}")

    outdir.mkdir(parents=True, exist_ok=True)
    _prepare_import_path()

    StemSplitterEngine = _load_stem_splitter_engine()

    StemSplitterEngine.validate_params(args.margin, args.wiener)

    audio, sample_rate = sf.read(str(input_path), dtype="float64", always_2d=False)
    tonal, transient, noise = StemSplitterEngine.separate(
        audio,
        int(sample_rate),
        margin=float(args.margin),
        wiener_iters=int(args.wiener),
        hop_length=int(args.hop),
    )

    paths = _output_paths(input_path, outdir)
    sf.write(str(paths["tonal"]), tonal, sample_rate, subtype="PCM_24")
    sf.write(str(paths["transient"]), transient, sample_rate, subtype="PCM_24")
    sf.write(str(paths["noise"]), noise, sample_rate, subtype="PCM_24")

    # ASCII-only JSON survives cmd.exe redirect code pages; Lua decoder expands \u escapes.
    print(json.dumps({name: str(path) for name, path in paths.items()}, ensure_ascii=True), flush=True)
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    try:
        return run(argv)
    except SystemExit:
        raise
    except Exception as exc:
        sys.stderr.write(
            "[LeeSplitterCLI:EXCEPTION] " + type(exc).__name__ + ": " + str(exc) + "\n"
        )
        traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
