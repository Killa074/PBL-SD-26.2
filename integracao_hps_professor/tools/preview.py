"""Lossless format conversion of the real HDL VGA capture; no scene redraw."""
from pathlib import Path
from PIL import Image
root = Path(__file__).resolve().parents[1]
source = root / "simulation" / "hps_demo.ppm"
dest = source.with_suffix(".png")
with Image.open(source) as capture:
    assert capture.size == (640, 480), capture.size
    capture.save(dest)
print(dest)
