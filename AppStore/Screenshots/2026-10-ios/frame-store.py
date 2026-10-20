#!/usr/bin/env python3
"""Frame approved native captures locally. Does not capture or upload screenshots."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


BASE = Path(__file__).resolve().parent


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def run(argv):
    subprocess.run([str(value) for value in argv], check=True)


def dimensions(path):
    result = subprocess.run(["magick", "identify", "-format", "%w %h", str(path)],
                            check=True, text=True, capture_output=True)
    return tuple(int(value) for value in result.stdout.split())


def caption(text, width, font_size, color, font, gravity, offset):
    return ["(", "-background", "none", "-fill", color, "-font", font,
            "-gravity", "center", "-pointsize", str(font_size), "-size", f"{width - 160}x",
            f"caption:{text}", ")", "-gravity", gravity, "-geometry", f"+0+{offset}", "-composite"]


def compose(frame, output, family, copy, design, font, bold_font):
    layout = design["families"][family]
    width, height = layout["size"]
    frame_width, frame_height = dimensions(frame)
    fit_width, fit_height = layout["frame_fit"]
    scale = min(fit_width / frame_width, fit_height / frame_height, 1)
    scaled_width, scaled_height = round(frame_width * scale), round(frame_height * scale)
    frame_top = layout["frame_center_y"] - scaled_height // 2
    palette = design["background"]
    # Composite the untouched framed capture first; captions occupy explicit margins outside the device.
    command = ["magick", "-size", f"{width}x{height}", f"xc:{palette[0]}",
               "-sparse-color", "Barycentric",
               f"0,0 {palette[0]} {width // 2},{height // 3} {palette[1]} {width},{height} {palette[2]}",
               "-blur", "0x48", "(", str(frame), "-filter", "Lanczos", "-resize",
               f"{scaled_width}x{scaled_height}!", ")", "-gravity", "north", "-geometry",
               f"+0+{frame_top}", "-composite"]
    command += caption(copy["title"], width, layout["title_font_size"], design["title_color"],
                       bold_font, "north", layout["title_y"])
    command += caption(copy["subtitle"], width, layout["subtitle_font_size"], design["subtitle_color"],
                       font, "north", layout["subtitle_y"])
    command += caption(design["disclosure"], width, layout["disclosure_font_size"], design["disclosure_color"],
                       font, "south", layout["disclosure_bottom"])
    command += ["-alpha", "off", "-colorspace", "sRGB", "-depth", "8", "-type", "TrueColor",
                "-strip", f"PNG24:{output}"]
    run(command)
    if dimensions(output) != tuple(layout["size"]):
        raise RuntimeError(f"Incorrect final dimensions: {output}")
    channels = subprocess.run(["magick", "identify", "-format", "%[channels]", str(output)],
                              check=True, text=True, capture_output=True).stdout.lower()
    if "a" in channels:
        raise RuntimeError(f"Final screenshot has transparency: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, default=BASE / "raw")
    parser.add_argument("--iphone-dir", type=Path)
    parser.add_argument("--ipad-dir", type=Path)
    parser.add_argument("--output-dir", type=Path, default=BASE / "framed")
    parser.add_argument("--screens", help="Comma-separated screenshot IDs for a bounded preview; default renders all.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    design = read_json(BASE / "design.json")
    if args.screens:
        selected = set(args.screens.split(","))
        known = {screen["id"] for screen in design["screens"]}
        if selected - known:
            parser.error("Unknown screenshot IDs: " + ", ".join(sorted(selected - known)))
        design["screens"] = [screen for screen in design["screens"] if screen["id"] in selected]
    inputs = {"iphone": args.iphone_dir or args.raw_dir / "iphone",
              "ipad": args.ipad_dir or args.raw_dir / "ipad"}
    jobs = []
    for screen in design["screens"]:
        copy = read_json(BASE / "copy" / (screen["id"] + ".json"))[design["locale"]]
        for family in design["families"]:
            source = (inputs[family] / (screen["id"] + ".png")).resolve()
            output = args.output_dir.resolve() / design["locale"] / family / source.name
            jobs.append((screen, family, source, output, copy))
    if args.dry_run:
        print(json.dumps([{"source": str(source), "present": source.is_file(), "output": str(output),
                           "title": copy["title"], "subtitle": copy["subtitle"], "disclosure": design["disclosure"]}
                          for _, _, source, output, copy in jobs], indent=2))
        return
    scratch_value = os.environ.get("CLEAN_DEVELOPMENT_SCRATCH_ROOT")
    if not scratch_value:
        raise RuntimeError("Load ~/dev/machine/env.zsh and run through Clean Development; scratch routing is required.")
    scratch = Path(scratch_value)
    if not scratch.is_dir() or not os.access(scratch, os.W_OK):
        raise RuntimeError(f"Selected scratch directory is unavailable: {scratch}")
    for dependency in ("asc-screens", "magick"):
        if shutil.which(dependency) is None:
            raise RuntimeError(f"Missing installed tool: {dependency}")
    font = "/System/Library/Fonts/Supplemental/Arial.ttf"
    bold_font = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
    if not Path(font).is_file() or not Path(bold_font).is_file():
        raise RuntimeError("The system Arial regular/bold fonts are required; no fonts are installed by this script.")
    for _, family, source, output, _ in jobs:
        if not source.is_file():
            raise FileNotFoundError(source)
        if dimensions(source) != tuple(design["families"][family]["size"]):
            raise RuntimeError(f"Raw capture dimensions do not match the approved {family} canvas: {source}")
        if output.exists():
            raise FileExistsError(f"Choose a fresh output directory; existing output will not be replaced: {output}")
    work = Path(tempfile.mkdtemp(prefix="codexex-store-framing-", dir=scratch))
    receipt = []
    for screen, family, source, output, copy in jobs:
        job = work / screen["id"] / family
        staged = job / "raw" / family
        staged.mkdir(parents=True)
        shutil.copy2(source, staged / source.name)
        config = read_json(BASE / "configs" / (screen["id"] + ".json"))
        config.update(source=str(job / "raw"), output_root=str(job / "asc_out"), kind=family + "-latest",
                      copy_file=str(BASE / "copy" / (screen["id"] + ".json")))
        config_path = job / "runtime-config.json"
        config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
        run(["asc-screens", "--config", config_path])
        frame = job / "asc_out" / design["locale"] / "_framed" / family / (source.stem + "_framed.png")
        if not frame.is_file():
            raise RuntimeError(f"Framing did not produce the expected real-device image: {frame}")
        output.parent.mkdir(parents=True, exist_ok=True)
        compose(frame, output, family, copy, design, font, bold_font)
        receipt.append({"id": screen["id"], "view": screen["view"], "family": family,
                        "source": str(source), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                        "output": str(output), "size": design["families"][family]["size"], **copy,
                        "disclosure": design["disclosure"]})
    manifest = args.output_dir.resolve() / "review.json"
    manifest.write_text(json.dumps({"locale": design["locale"], "count": len(receipt),
                                    "staging": str(work), "screenshots": receipt}, indent=2) + "\n", encoding="utf-8")
    print(f"Ready for visual review: {len(receipt)} images; {manifest}")


if __name__ == "__main__":
    main()
