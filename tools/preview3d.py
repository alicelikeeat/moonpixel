#!/usr/bin/env python3
"""Draw the 3D meshes of a town without any Apple framework, to look at them on Linux.

  cd ios && MP_DUMP3D=/tmp/town.bin swift test -c release -Xswiftc -enable-testing --filter testDumpATown
  python3 tools/preview3d.py /tmp/town.bin out.png [yaw_degrees] [pitch_degrees] [distance_tiles]

A plain z-buffer rasteriser: the colours are exactly the ones the meshes carry (their shading is
baked in), so this shows shapes and proportions, not what RealityKit adds on a device.
"""
import sys
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
yaw = np.radians(float(sys.argv[3]) if len(sys.argv) > 3 else 0)
pitch = np.radians(float(sys.argv[4]) if len(sys.argv) > 4 else 50)
dist = float(sys.argv[5]) if len(sys.argv) > 5 else 26
W, H, FOV = 1280, 720, np.radians(50)

raw = np.fromfile(src, dtype=np.float32)
cx, cz = raw[0], raw[1]
tri = raw[2:].reshape(-1, 12)
P = tri[:, :9].reshape(-1, 3, 3).astype(np.float64)
C = tri[:, 9:12]

near = np.abs(P[:, 0, 0] - cx) + np.abs(P[:, 0, 2] - cz) < 3
target = np.array([cx, P[near][:, :, 1].min() if near.any() else 0.0, cz])
eye = target + dist * np.array([np.sin(yaw) * np.cos(pitch), np.sin(pitch), np.cos(yaw) * np.cos(pitch)])
f = target - eye; f /= np.linalg.norm(f)
r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r)
u = np.cross(r, f)
V = P - eye
x, y, z = V @ r, V @ u, V @ f
keep = (z > 0.3).all(axis=1)
x, y, z, C = x[keep], y[keep], z[keep], C[keep]
k = (H / 2) / np.tan(FOV / 2)
sx, sy = W / 2 + k * x / z, H / 2 - k * y / z

img = np.zeros((H, W, 3), dtype=np.float32) + np.array([0.56, 0.74, 0.90], dtype=np.float32)
zb = np.full((H, W), np.inf)
order = np.argsort(-z.mean(axis=1))
for i in order:
    xs, ys, zs = sx[i], sy[i], z[i]
    x0, x1 = int(max(0, np.floor(xs.min()))), int(min(W - 1, np.ceil(xs.max())))
    y0, y1 = int(max(0, np.floor(ys.min()))), int(min(H - 1, np.ceil(ys.max())))
    if x0 > x1 or y0 > y1:
        continue
    d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
    if d >= 0:          # back face (screen y runs down, so front faces come out negative)
        continue
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    a = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
    b = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
    c = 1 - a - b
    inside = (a >= 0) & (b >= 0) & (c >= 0)
    if not inside.any():
        continue
    zz = 1 / (a / zs[0] + b / zs[1] + c / zs[2] + 1e-12)
    sub = zb[y0:y1 + 1, x0:x1 + 1]
    hit = inside & (zz < sub)
    sub[hit] = zz[hit]
    img[y0:y1 + 1, x0:x1 + 1][hit] = C[i]
Image.fromarray((img.clip(0, 1) * 255).astype(np.uint8)).save(dst)
print(f"{len(order)} triangles -> {dst}")
