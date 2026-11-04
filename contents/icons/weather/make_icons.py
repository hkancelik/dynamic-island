#!/usr/bin/env python3
"""Hava durumu simgelerini üretir (kendi çizimimiz, GPL-3.0). Çalıştır: python3 make_icons.py

Her simge 24×24, renkli ve düz; "Apple Hava Durumu" gibi sade: sarı güneş, gri bulut, mavi damla.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SUN, MOON, CLOUD, CLOUD_DK, CLOUD_BK = "#ffd60a", "#e5e5ea", "#f2f2f7", "#aeaeb2", "#8e8e93"
DROP, SNOW, BOLT, FOG = "#64d2ff", "#ffffff", "#ffd60a", "#aeaeb2"
CLOUD_PATH = "M6.5 19.5a4.25 4.25 0 0 1-.4-8.48 6 6 0 0 1 11.6-1.2A4.9 4.9 0 0 1 17.5 19.5z"


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">%s</svg>\n' % body)


def cloud(fill=CLOUD, tx=0.0, ty=0.0, s=1.0):
    return '<path transform="translate(%g %g) scale(%g)" d="%s" fill="%s"/>' % (tx, ty, s, CLOUD_PATH, fill)


def sun(cx, cy, r, rays=True, ray_in=None, ray_out=None, w=1.8):
    ray_in = ray_in if ray_in is not None else r + 2.6
    ray_out = ray_out if ray_out is not None else r + 5.4
    out = '<circle cx="%g" cy="%g" r="%g" fill="%s"/>' % (cx, cy, r, SUN)
    if rays:
        import math
        for i in range(8):
            a = math.radians(i * 45)
            x1, y1 = cx + ray_in * math.cos(a), cy + ray_in * math.sin(a)
            x2, y2 = cx + ray_out * math.cos(a), cy + ray_out * math.sin(a)
            out += '<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%g" stroke-linecap="round"/>' % (x1, y1, x2, y2, SUN, w)
    return out


def moon(scale=1.0, tx=0.0, ty=0.0):
    return ('<path transform="translate(%g %g) scale(%g)" fill="%s" '
            'd="M19.5 14.6A8 8 0 0 1 9.4 4.5a8 8 0 1 0 10.1 10.1z"/>' % (tx, ty, scale, MOON))


def drops(color, xs=(8.2, 12.2, 16.2), y0=17.6, y1=21.6):
    return "".join('<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="1.9" stroke-linecap="round"/>'
                   % (x + 0.7, y0, x - 0.7, y1, color) for x in xs)


ICONS = {
    "sun": svg(sun(12, 12, 4.4)),
    "moon": svg(moon()),
    "sun-cloud": svg(sun(9.2, 9.2, 3.5, ray_in=5.6, ray_out=7.6, w=1.6) + cloud(CLOUD, 4.2, 4.4, 0.8)),
    "moon-cloud": svg(moon(0.78, 0.6, -0.4) + cloud(CLOUD, 4.2, 4.4, 0.8)),
    "cloud": svg(cloud(CLOUD, 0, 0.2)),
    "overcast": svg(cloud(CLOUD_BK, 5.0, -3.2, 0.78) + cloud(CLOUD, -0.4, 1.2, 0.95)),
    "rain": svg(cloud(CLOUD_DK, 0, -3.2, 0.96) + drops(DROP)),
    "sleet": svg(cloud(CLOUD_DK, 0, -3.2, 0.96) + drops(DROP, xs=(8.2, 16.2))
                 + '<circle cx="12.2" cy="19.4" r="1.25" fill="%s"/>' % SNOW),
    "snow": svg(cloud(CLOUD_DK, 0, -3.2, 0.96)
                + "".join('<circle cx="%g" cy="%g" r="1.3" fill="%s"/>' % (x, y, SNOW) for x, y in ((8, 18.3), (12.2, 20.6), (16.4, 18.3)))),
    "storm": svg(cloud(CLOUD_BK, 0, -3.4, 0.96)
                 + '<path d="M12.9 14.2 8.8 19.6h2.9l-1 3.6 4.7-6h-3z" fill="%s"/>' % BOLT),
    "fog": svg(cloud(CLOUD, 1.4, -4.4, 0.8)
               + "".join('<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="1.9" stroke-linecap="round"/>'
                         % (x1, y, x2, y, FOG) for x1, x2, y in ((4, 18, 15.4), (6.5, 20, 18.7), (4, 15, 22)))),
}

# kapalı sekme çubuğu simgesi: tek renk, çizgi stili (Isle simgeleriyle uyumlu)
TAB_ICON = ('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">'
            '<path fill="none" stroke="#ffffff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" '
            'd="M4.4 12.6a2.9 2.9 0 0 1-.3-5.78 4.1 4.1 0 0 1 7.9-.8 3.3 3.3 0 0 1 .5 6.58z"/></svg>\n')

if __name__ == "__main__":
    for name, body in ICONS.items():
        with open(os.path.join(HERE, name + ".svg"), "w") as f:
            f.write(body)
    with open(os.path.join(HERE, "..", "isle-weather.svg"), "w") as f:
        f.write(TAB_ICON)
    print("yazıldı:", ", ".join(sorted(ICONS)), "+ isle-weather.svg")
