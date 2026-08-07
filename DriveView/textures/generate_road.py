#!/usr/bin/env python3
"""
Generates the Drive View road textures.

Procedural rather than a stock photo on purpose: a photo of a road arrives with
its own sun baked into it, which fights the scene lights and looks wrong the
moment the camera orbits. These are pure material maps — albedo with no
lighting, a normal map, and a roughness map — so the scene's own lights do all
the shading.

The surface is chevron block paving rather than plain tarmac: near-black facets
separated by recessed grooves, with the arrows pointing down the road. The
grooves are what make it read as modern — they catch a highlight along their
edges, so the road has structure instead of being a flat dark sheet.

Everything except the range-fade mask is tileable. The pattern tiles by construction
(a whole number of cells per tile) and the grain by being filtered in the
frequency domain, where a DFT is periodic and so wraps with no seam.

    python3 generate_road.py

Writes into the directory this script lives in. Re-run after changing any
constant below; the PNGs are committed so a normal build never needs this.
"""

import pathlib
import numpy as np
from PIL import Image

HERE = pathlib.Path(__file__).parent

TILE = 512          # tileable maps (basecolor / normal / roughness)
MASK = 512          # the range-fade mask

# --- paving pattern ---------------------------------------------------------
# Cells per tile. GroundPlane.qml maps one tile to 2.5 m, so 4 x 4 gives 62 cm
# square cells. 8 rows was the first try and it read as herringbone fabric
# rather than paving — squashed chevrons repeating too often down the road.
CELLS_X = 4
CELLS_Y = 4

GROOVE_W   = 0.055  # groove half-width, as a fraction of cell height
BEVEL_W    = 0.16   # width of the chamfer either side of a groove
ARM_SLOPE  = 1.0    # 1.0 puts the apex a full cell above the arm ends

# See build_pattern: the ground mesh's UVs are not laid out the way you would
# guess, and the arrows come out pointing across the road without this.
TRANSPOSE  = False
FLIP       = False  # reverses which way the arrows point along the road

# --- tone -------------------------------------------------------------------
# sRGB 8-bit. Much darker than tarmac: the reference road is nearly black and
# reads by its pattern, not its brightness. It cannot go all the way to black
# though — the background behind the fade is #080a0d, and a road that dark
# would dissolve into it with no visible falloff at all.
BASE_TONE    = 50
GROOVE_TONE  = 16   # inside the grooves
FACET_VAR    = 4.5  # cell-to-cell tone jitter; stops it looking printed
GRAIN_AMP    = 3.0  # fine surface speckle

NORMAL_STRENGTH = 3.2   # bevel depth. This is what catches the highlight.

# Sealed block paving is glossier than tarmac, which is where the sheen in the
# reference comes from. Grooves stay rough — dirt collects in them.
#
# Not glossier than this, though: the scene's fill light rakes across the road
# at 20 degrees, and a tighter highlight than this breaks into crawling
# glitter along the groove bevels wherever it hits.
ROUGH_FACET  = 0.70
ROUGH_GROOVE = 0.80
ROUGH_VAR    = 0.06

# --- range fade -------------------------------------------------------------
# Fractions of the plane's half-width, so they track `size` in GroundPlane.qml.
# Every point on the plane's boundary is at radius >= 1.0, so ending the fade at
# 0.8 guarantees the plane's own rectangular edge is always fully transparent
# and can never show up as a hard line, whatever size the plane is given.
FADE_SOLID_R = 0.15
FADE_ZERO_R  = 0.80



def band_noise(n, seed, centre, width):
    """Tileable band-limited noise, normalised to zero mean / unit variance.

    `centre` and `width` are in cycles across the tile, so 200 is fine grain and
    8 is a slow wobble.
    """
    rng = np.random.default_rng(seed)
    spectrum = np.fft.fft2(rng.normal(size=(n, n)))

    freq = np.fft.fftfreq(n) * n
    radius = np.hypot(freq[None, :], freq[:, None])
    spectrum *= np.exp(-((radius - centre) ** 2) / (2.0 * width ** 2))

    out = np.real(np.fft.ifft2(spectrum))
    return (out - out.mean()) / (out.std() + 1e-9)


def smootherstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def build_pattern():
    """Signed distance to the nearest groove, plus a per-cell id.

    Distance is in units of cell height and is 0 on the groove centreline,
    rising as you move onto a facet.
    """
    ax = (np.arange(TILE) + 0.5) / TILE
    u = ax[None, :] * CELLS_X          # x, in cells
    v = ax[:, None] * CELLS_Y          # y, in cells (down the screen)

    cu = u % 1.0
    cv = v % 1.0

    # The chevron. Apex at the top centre of the cell, arms falling to the
    # bottom corners, so the arrow points away down the road.
    arm = ARM_SLOPE * np.abs(2.0 * cu - 1.0)
    d_chevron = np.abs(cv - arm)

    # Wrap: an arm leaving the bottom of one cell is the same groove as the one
    # entering the top of the cell below, so the zigzag has to be continuous
    # across the seam.
    d_chevron = np.minimum(d_chevron, np.abs(cv - arm + 1.0))
    d_chevron = np.minimum(d_chevron, np.abs(cv - arm - 1.0))

    # Column separators. Scaled into cell-height units so one groove width
    # constant covers both families of line.
    d_column = np.minimum(cu, 1.0 - cu) * (CELLS_Y / CELLS_X)

    dist = np.minimum(d_chevron, d_column)

    # Cell id, used only to jitter facet tone.
    cell_id = (np.floor(u).astype(int) * 7919 + np.floor(v).astype(int) * 104729)

    # Transpose to point the arrows down the road.
    #
    # The built-in "#Rectangle" mesh does not lay its UVs out the way you would
    # guess once it is rotated flat: its V axis ends up running along world X,
    # across the road, not along it. Built the obvious way the chevrons come out
    # aiming at the kerb. Rotating the pattern here rather than rotating the UVs
    # in QML keeps the tiling maths in one place.
    if TRANSPOSE:
        dist = dist.T
        cell_id = cell_id.T
    if FLIP:
        dist = dist[:, ::-1] if TRANSPOSE else dist[::-1, :]
        cell_id = cell_id[:, ::-1] if TRANSPOSE else cell_id[::-1, :]

    return np.ascontiguousarray(dist), np.ascontiguousarray(cell_id)


def groove_mask(dist):
    """1 inside a groove, 0 on a facet, with the bevel ramping between."""
    return 1.0 - smootherstep((dist - GROOVE_W) / BEVEL_W)


def build_height(dist):
    """Facets flat and proud, grooves recessed, chamfer in between."""
    return smootherstep((dist - GROOVE_W) / BEVEL_W)


def write_basecolor(dist, cell_id, grain):
    inside = groove_mask(dist)

    rng = np.random.default_rng(4)
    jitter = (rng.random(2 ** 16) - 0.5) * 2.0
    tone = BASE_TONE + jitter[cell_id % (2 ** 16)] * FACET_VAR
    tone = tone + grain * GRAIN_AMP

    tone = tone * (1.0 - inside) + GROOVE_TONE * inside
    tone = np.clip(tone, 0, 255)

    # Slight cool cast. Neutral grey reads as plastic under white light.
    rgb = np.stack([tone * 0.97, tone * 0.99, tone * 1.05], axis=-1)
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").save(
        HERE / "road_basecolor.png", optimize=True)


def write_normal(dist, grain):
    height = build_height(dist) + grain * 0.02

    # np.roll wraps, so the gradients stay seamless at the tile border.
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5

    nx = -dx * NORMAL_STRENGTH * TILE / 512.0
    ny = -dy * NORMAL_STRENGTH * TILE / 512.0
    nz = np.ones_like(nx)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)

    img = np.stack([nx * inv, ny * inv, nz * inv], axis=-1)
    img = ((img * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)
    Image.fromarray(img, "RGB").save(HERE / "road_normal.png", optimize=True)


def write_roughness(dist, grain):
    inside = groove_mask(dist)
    rough = ROUGH_FACET * (1.0 - inside) + ROUGH_GROOVE * inside
    rough = rough + grain * ROUGH_VAR
    img = (np.clip(rough, 0, 1) * 255.0).astype(np.uint8)
    Image.fromarray(img, "L").save(HERE / "road_roughness.png", optimize=True)


def write_fade():
    axis = (np.arange(MASK) + 0.5) / MASK * 2.0 - 1.0
    radius = np.hypot(axis[None, :], axis[:, None])

    t = (radius - FADE_SOLID_R) / (FADE_ZERO_R - FADE_SOLID_R)
    alpha = 1.0 - smootherstep(t)

    # An 8-bit ramp this long bands visibly on a gradient background. A dither
    # of well under one level is invisible on its own but breaks the contours.
    rng = np.random.default_rng(99)
    alpha += rng.uniform(-0.6, 0.6, size=alpha.shape) / 255.0

    img = (np.clip(alpha, 0, 1) * 255.0).astype(np.uint8)
    Image.fromarray(img, "L").save(HERE / "range_fade.png", optimize=True)



def main():
    dist, cell_id = build_pattern()
    grain = band_noise(TILE, 11, centre=170, width=70)

    write_basecolor(dist, cell_id, grain)
    write_normal(dist, grain)
    write_roughness(dist, grain)
    write_fade()

    for f in sorted(HERE.glob("*.png")):
        print(f"{f.name:24} {f.stat().st_size / 1024:7.1f} KiB")


if __name__ == "__main__":
    main()
