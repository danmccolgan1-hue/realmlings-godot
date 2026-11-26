"""Draw a recorded HTML canvas command list (tools/record_canvas.js) into a PIL image.

A small Canvas 2D in Python: the current transform, save/restore, paths of lines, arcs, ellipses and quadratic and
cubic curves, fill (nonzero, by union of subpaths), stroke (round joins and caps), clip, fillRect/strokeRect, and
#rgb / #rrggbb / rgba() colors. Enough for the web game's isometric drawing kit (buildings.js, woodbld.js). Drawn
supersampled and shrunk for smooth edges.
"""
import math
import re
import numpy as np
from PIL import Image, ImageChops, ImageDraw


def parse_color(s):
    s = str(s).strip()
    if s.startswith('#'):
        h = s[1:]
        if len(h) == 3:
            h = ''.join(ch * 2 for ch in h)
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)
    m = re.match(r'rgba?\(([^)]*)\)', s)
    if m:
        p = [float(v) for v in m.group(1).split(',')]
        a = p[3] if len(p) > 3 else 1.0
        return (int(round(p[0])), int(round(p[1])), int(round(p[2])), int(round(a * 255)))
    return {'white': (255, 255, 255, 255), 'black': (0, 0, 0, 255), 'transparent': (0, 0, 0, 0)}.get(s, (0, 0, 0, 255))


class Canvas:
    def __init__(self, w, h, pre=(1, 0, 0, 1, 0, 0)):
        self.w, self.h = w, h
        self.img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        self.m = pre                     # a, b, c, d, e, f (x' = a x + c y + e, y' = b x + d y + f)
        self.fill_style = (0, 0, 0, 255)
        self.stroke_style = (0, 0, 0, 255)
        self.line_width = 1.0
        self.line_cap = 'butt'
        self.alpha = 1.0
        self.clip = None                 # an 'L' mask, or None
        self.stack = []
        self.subs = []                   # [[points], closed]

    # --- transform ---
    def _mul(self, t):
        a, b, c, d, e, f = self.m
        A, B, C, D, E, F = t
        self.m = (a * A + c * B, b * A + d * B, a * C + c * D, b * C + d * D, a * E + c * F + e, b * E + d * F + f)

    def _pt(self, x, y):
        a, b, c, d, e, f = self.m
        return (a * x + c * y + e, b * x + d * y + f)

    def _scale_factor(self):
        a, b, c, d, _, _ = self.m
        return math.sqrt(abs(a * d - b * c))

    # --- the commands ---
    def scale(self, x, y):
        self._mul((x, 0, 0, y, 0, 0))

    def translate(self, x, y):
        self._mul((1, 0, 0, 1, x, y))

    def rotate(self, r):
        c, s = math.cos(r), math.sin(r)
        self._mul((c, s, -s, c, 0, 0))

    def transform(self, a, b, c, d, e, f):
        self._mul((a, b, c, d, e, f))

    def setTransform(self, a, b, c, d, e, f):
        self.m = (a, b, c, d, e, f)

    def save(self):
        self.stack.append((self.m, self.fill_style, self.stroke_style, self.line_width, self.line_cap, self.alpha, self.clip))

    def restore(self):
        if self.stack:
            self.m, self.fill_style, self.stroke_style, self.line_width, self.line_cap, self.alpha, self.clip = self.stack.pop()

    def beginPath(self):
        self.subs = []

    def moveTo(self, x, y):
        self.subs.append([[self._pt(x, y)], False])

    def lineTo(self, x, y):
        if not self.subs:
            self.moveTo(x, y)
        else:
            self.subs[-1][0].append(self._pt(x, y))

    def closePath(self):
        if self.subs and self.subs[-1][0]:
            self.subs[-1][1] = True
            self.subs.append([[self.subs[-1][0][0]], False])

    def _sweep(self, a0, a1, ccw):
        tau = 2 * math.pi
        if not ccw:
            if a1 - a0 >= tau:
                return a0, a0 + tau
            while a1 < a0:
                a1 += tau
            return a0, a1
        if a0 - a1 >= tau:
            return a0, a0 - tau
        while a1 > a0:
            a1 -= tau
        return a0, a1

    def ellipse(self, x, y, rx, ry, rot, a0, a1, ccw=False):
        a0, a1 = self._sweep(a0, a1, ccw)
        n = max(8, int(abs(a1 - a0) / (2 * math.pi) * 96))
        cr, sr = math.cos(rot), math.sin(rot)
        pts = []
        for i in range(n + 1):
            t = a0 + (a1 - a0) * i / n
            px, py = rx * math.cos(t), ry * math.sin(t)
            pts.append(self._pt(x + px * cr - py * sr, y + px * sr + py * cr))
        if self.subs and self.subs[-1][0]:
            self.subs[-1][0].extend(pts)
        else:
            self.subs.append([pts, False])

    def arc(self, x, y, r, a0, a1, ccw=False):
        self.ellipse(x, y, r, r, 0, a0, a1, ccw)

    def quadraticCurveTo(self, cx, cy, x, y):
        if not self.subs:
            self.moveTo(cx, cy)
        p0 = self.subs[-1][0][-1]
        c = self._pt(cx, cy)
        p1 = self._pt(x, y)
        for i in range(1, 17):
            t = i / 16
            self.subs[-1][0].append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]))

    def bezierCurveTo(self, c1x, c1y, c2x, c2y, x, y):
        if not self.subs:
            self.moveTo(c1x, c1y)
        p0 = self.subs[-1][0][-1]
        c1, c2, p1 = self._pt(c1x, c1y), self._pt(c2x, c2y), self._pt(x, y)
        for i in range(1, 21):
            t = i / 20
            u = 1 - t
            self.subs[-1][0].append((u ** 3 * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t ** 3 * p1[0],
                                     u ** 3 * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t ** 3 * p1[1]))

    def rect(self, x, y, w, h):
        self.moveTo(x, y)
        self.lineTo(x + w, y)
        self.lineTo(x + w, y + h)
        self.lineTo(x, y + h)
        self.closePath()

    # --- painting ---
    def _fill_mask(self):
        mk = Image.new('L', (self.w, self.h), 0)
        d = ImageDraw.Draw(mk)
        for pts, _ in self.subs:
            if len(pts) >= 3:
                d.polygon(pts, fill=255)
        return mk

    def _gradient_layer(self, gr, mask):
        """A linear gradient (in the transform at the time of painting) as an RGBA layer under mask."""
        x0, y0, x1, y1 = gr['args']
        p0, p1 = self._pt(x0, y0), self._pt(x1, y1)
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        L2 = dx * dx + dy * dy or 1.0
        ys, xs = np.mgrid[0:self.h, 0:self.w].astype(np.float64)
        t = np.clip(((xs + 0.5 - p0[0]) * dx + (ys + 0.5 - p0[1]) * dy) / L2, 0.0, 1.0)
        stops = [(float(o), parse_color(c)) for o, c in gr['stops']]
        out = np.zeros((self.h, self.w, 4), np.float64)
        out[...] = stops[0][1]
        for (o0, c0), (o1, c1) in zip(stops, stops[1:]):
            sel = (t >= o0) & (t <= o1)
            f = np.zeros_like(t) if o1 == o0 else (t - o0) / (o1 - o0)
            for ch in range(4):
                out[..., ch] = np.where(sel, c0[ch] + (c1[ch] - c0[ch]) * f, out[..., ch])
        out[..., 3] = out[..., 3] * (np.asarray(mask, np.float64) / 255.0) * self.alpha
        return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), 'RGBA')

    def _paint(self, mask, col):
        if self.clip is not None:
            mask = ImageChops.multiply(mask, self.clip)
        if isinstance(col, dict):
            self.img = Image.alpha_composite(self.img, self._gradient_layer(col, mask))
            return
        a = col[3] / 255.0 * self.alpha
        if a <= 0:
            return
        if a < 1:
            mask = mask.point(lambda v: int(v * a + 0.5))
        layer = Image.new('RGBA', (self.w, self.h), col[:3] + (0,))
        layer.putalpha(mask)
        self.img = Image.alpha_composite(self.img, layer)

    def fill(self, *_):
        self._paint(self._fill_mask(), self.fill_style)

    def stroke(self):
        w = max(1.0, self.line_width * self._scale_factor())
        mk = Image.new('L', (self.w, self.h), 0)
        d = ImageDraw.Draw(mk)
        r = w / 2
        for pts, closed in self.subs:
            if len(pts) < 2:
                continue
            seq = pts + [pts[0]] if closed else pts
            d.line(seq, fill=255, width=max(1, int(round(w))), joint='curve')
            if self.line_cap == 'round' and not closed:
                for (x, y) in (seq[0], seq[-1]):
                    d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        self._paint(mk, self.stroke_style)

    def clip_(self):
        mk = self._fill_mask()
        self.clip = mk if self.clip is None else ImageChops.multiply(self.clip, mk)

    def fillRect(self, x, y, w, h):
        keep = self.subs
        self.subs = []
        self.rect(x, y, w, h)
        self.fill()
        self.subs = keep

    def strokeRect(self, x, y, w, h):
        keep = self.subs
        self.subs = []
        self.rect(x, y, w, h)
        self.stroke()
        self.subs = keep

    def set(self, k, v):
        if k == 'fillStyle':
            self.fill_style = parse_color(v) if isinstance(v, str) else v if isinstance(v, dict) and v.get('gradient') == 'linear' else self.fill_style
        elif k == 'strokeStyle':
            self.stroke_style = parse_color(v) if isinstance(v, str) else v if isinstance(v, dict) and v.get('gradient') == 'linear' else self.stroke_style
        elif k == 'lineWidth':
            self.line_width = float(v)
        elif k == 'lineCap':
            self.line_cap = v
        elif k == 'globalAlpha':
            self.alpha = float(v)


def replay(cmds, w, h, pre):
    """Run a command list on a fresh canvas of w x h pixels; pre: the transform applied before the recorded ones."""
    c = Canvas(w, h, pre)
    for cmd in cmds:
        op, args = cmd[0], cmd[1:]
        if op == 'set':
            c.set(args[0], args[1])
        elif op == 'clip':
            c.clip_()
        elif hasattr(c, op):
            getattr(c, op)(*args)
        else:
            raise ValueError('canvas command not supported: ' + op)
    return c.img
