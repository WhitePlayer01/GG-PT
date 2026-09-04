"""Remove the generated checkerboard after the user's explicit local-edit approval."""
from pathlib import Path
import sys
import cv2
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[1]
variant = '-' + sys.argv[1] if len(sys.argv) > 1 else ''
source = root / f'output/listening-design/guan-yu-listening{variant}-concept.png'
rgb = np.array(Image.open(source).convert('RGB'))
low, high = rgb.min(axis=2), rgb.max(axis=2)
neutral_background = ((low > 195) & ((high.astype(int) - low.astype(int)) < 26)).astype(np.uint8)
count, labels = cv2.connectedComponents(neutral_background, connectivity=8)
edge_labels = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
edge_labels = edge_labels[edge_labels != 0]
background = np.isin(labels, edge_labels)
# Preserve enclosed white fabric and highlights. Feather just the outline into transparency.
opaque = (~background).astype(np.uint8) * 255
opaque = cv2.erode(opaque, np.ones((3, 3), np.uint8), iterations=1)
alpha = cv2.GaussianBlur(opaque, (3, 3), 0.55)
alpha[background] = 0
rgba = np.dstack([rgb, alpha])
rgba[alpha == 0, :3] = 0
output = root / f'Sources/PetSorter/Resources/guan-yu-listening{variant}.png'
Image.fromarray(rgba).save(output)
# QA only: compare edges on light and dark desktops.
cutout = Image.fromarray(rgba)
views = []
for color in ['#f4f0e8', '#18232b']:
    base = Image.new('RGBA', cutout.size, color)
    base.alpha_composite(cutout)
    base.thumbnail((407, 543))
    views.append(base.convert('RGB'))
preview = Image.new('RGB', (814, 543))
for i, view in enumerate(views): preview.paste(view, (i * 407, 0))
preview.save(root / f'output/listening-design/transparency-check{variant}.jpg', quality=95)
print(f'{output}\nRGBA {cutout.size}; transparent pixels: {(alpha == 0).mean():.1%}')
