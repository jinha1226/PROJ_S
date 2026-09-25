"""Study copies of four Forge Master: Idle RPG sprites, redrawn as SVG from
measurements of its App Store screenshots (hero, skeleton, tree, barrel).

These are copies of another studio's art for learning its construction.
They are written to docs/art/forge-master-study/, which is not for shipping:
do not import them into the game or publish them.

Run: python3 tools/art/forge_master_study.py
"""
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402

OUT = flat.ROOT / "docs/art/forge-master-study"
INK = "#1a1216"


def line(width=5):
    return f'stroke="{INK}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"'


def doc(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'


# Coordinates are the screenshot's own pixels inside each crop.
HERO = doc(130, 150,
    '<ellipse cx="45" cy="138" rx="30" ry="8" fill="#b87a41"/>'
    f'<circle cx="47" cy="108" r="24" fill="#a4553d" {line()}/>'
    f'<path d="M33 118 Q41 109 49 118 Q41 123 33 118 Z" fill="none" {line(3)}/>'
    f'<circle cx="45" cy="72" r="19" fill="#feb78b" {line()}/>'
    f'<rect x="42" y="66" width="4.6" height="11" rx="2.2" fill="{INK}"/>'
    f'<rect x="52" y="66" width="4.6" height="11" rx="2.2" fill="{INK}"/>'
    '<clipPath id="hat"><path d="M8 60 Q7 64 12 64 L80 64 Q86 63 82 58 L68 42 Q65 39 61 42 L57 45 L55 39 Q52 34 47 36 Z"/></clipPath>'
    '<path d="M8 60 Q7 64 12 64 L80 64 Q86 63 82 58 L68 42 Q65 39 61 42 L57 45 L55 39 Q52 34 47 36 Z" fill="#3b46a6"/>'
    '<rect x="58" y="30" width="40" height="40" fill="#5864cc" clip-path="url(#hat)"/>'
    '<rect x="8" y="58" width="80" height="8" fill="#323c92" clip-path="url(#hat)"/>'
    f'<path d="M8 60 Q7 64 12 64 L80 64 Q86 63 82 58 L68 42 Q65 39 61 42 L57 45 L55 39 Q52 34 47 36 Z" fill="none" {line()}/>'
    f'<rect x="53.5" y="43" width="5" height="13" rx="2" fill="#3b46a6" {line(3)}/>'
    f'<path d="M10 94 Q9 88 18 89 L80 106 L78 118 L14 104 Q10 102 10 94 Z" fill="#9a3f12" {line()}/>'
    '<path d="M22 95 L70 108" stroke="#c9692d" stroke-width="3.5" stroke-linecap="round"/>'
    f'<path d="M79 107 L110 115 Q113 108 117 111 L115 133 Q111 135 110 129 L108 125 L78 118 Z" fill="#b3bdd4" {line()}/>'
    '<path d="M81 114 L108 121" stroke="#8e98b2" stroke-width="3" stroke-linecap="round"/>')

SKELETON = doc(105, 115,
    '<ellipse cx="56" cy="92" rx="22" ry="9" fill="#b87a41" transform="rotate(-18 56 92)"/>'
    '<clipPath id="skb"><circle cx="69" cy="66" r="23"/></clipPath>'
    '<circle cx="69" cy="66" r="23" fill="#b03a3b"/>'
    '<circle cx="82" cy="66" r="23" fill="#962d2f" clip-path="url(#skb)" transform="translate(4 0)"/>'
    f'<circle cx="69" cy="66" r="23" fill="none" {line()}/>'
    f'<path d="M64 71 L64 87 M57 75 L71 83 M57 83 L71 75" {line(3)}/>'
    f'<ellipse cx="70" cy="46" rx="11" ry="8" fill="#f0b48a" {line(4)}/>'
    '<clipPath id="sks"><path d="M43 27 A24 24 0 0 1 91 27 L91 32 Q91 42 82 42 L76 42 L75 46 L52 46 Q49 46 49 42 L49 40 Q43 36 43 27 Z"/></clipPath>'
    '<path d="M43 27 A24 24 0 0 1 91 27 L91 32 Q91 42 82 42 L76 42 L75 46 L52 46 Q49 46 49 42 L49 40 Q43 36 43 27 Z" fill="#f4ecd2"/>'
    '<rect x="77" y="0" width="30" height="50" fill="#d6c6a2" clip-path="url(#sks)"/>'
    '<rect x="48" y="38" width="30" height="10" fill="#e3d7b8" clip-path="url(#sks)"/>'
    f'<path d="M43 27 A24 24 0 0 1 91 27 L91 32 Q91 42 82 42 L76 42 L75 46 L52 46 Q49 46 49 42 L49 40 Q43 36 43 27 Z" fill="none" {line()}/>'
    f'<rect x="51" y="19" width="5.2" height="15" rx="2.6" fill="{INK}"/>'
    f'<rect x="61" y="19" width="5.2" height="15" rx="2.6" fill="{INK}"/>'
    '<g transform="translate(15 40) rotate(16.4)">'
    f'<path d="M14 5 L7 17 Q6 21 10 20 L22 7 Z" fill="#86683f" {line(4.5)}/>'
    f'<rect x="0" y="-6.5" width="81" height="13" rx="4" fill="#86683f" {line(4.5)}/>'
    '<rect x="7" y="-4" width="70" height="3" rx="1.5" fill="#a88a5c"/>'
    f'<ellipse cx="0" cy="0" rx="4" ry="6.5" fill="#efe2b4" {line(4)}/>'
    '</g>')

TREE = doc(200, 212,
    '<ellipse cx="105" cy="205" rx="55" ry="12" fill="#009e4c"/>'
    '<clipPath id="crown"><circle cx="100" cy="42" r="24"/><circle cx="65" cy="58" r="28"/><circle cx="138" cy="58" r="28"/>'
    '<circle cx="45" cy="104" r="30"/><circle cx="158" cy="104" r="28"/><circle cx="72" cy="134" r="26"/><circle cx="133" cy="134" r="26"/>'
    '<circle cx="100" cy="95" r="56"/></clipPath>'
    + "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="none" stroke="{INK}" stroke-width="7"/>'
              for x, y, r in ((100, 42, 24), (65, 58, 28), (138, 58, 28), (45, 104, 30), (158, 104, 28), (72, 134, 26), (133, 134, 26)))
    + '<rect x="0" y="0" width="200" height="212" fill="#b4dd82" clip-path="url(#crown)"/>'
    '<g clip-path="url(#crown)"><g transform="translate(-7 3)">'
    + "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#97cc55"/>'
              for x, y, r in ((100, 42, 24), (65, 58, 28), (138, 58, 28), (45, 104, 30), (158, 104, 28), (72, 134, 26), (133, 134, 26), (100, 95, 56)))
    + '</g></g>'
    '<clipPath id="trunk"><path d="M84 212 Q92 175 94 152 L77 139 Q72 135 76 131 Q80 128 84 132 L96 143 L94 122 Q94 117 99 117 Q104 117 104 122 L103 145 L120 130 Q125 127 128 131 Q130 135 126 139 L106 156 Q108 180 120 212 Z"/></clipPath>'
    '<path d="M84 212 Q92 175 94 152 L77 139 Q72 135 76 131 Q80 128 84 132 L96 143 L94 122 Q94 117 99 117 Q104 117 104 122 L103 145 L120 130 Q125 127 128 131 Q130 135 126 139 L106 156 Q108 180 120 212 Z" fill="#c25e00"/>'
    '<path d="M70 212 Q88 175 90 150 L70 130 L92 118 L99 150 Q97 180 96 212 Z" fill="#a74a00" clip-path="url(#trunk)"/>'
    f'<path d="M84 212 Q92 175 94 152 L77 139 Q72 135 76 131 Q80 128 84 132 L96 143 L94 122 Q94 117 99 117 Q104 117 104 122 L103 145 L120 130 Q125 127 128 131 Q130 135 126 139 L106 156 Q108 180 120 212" fill="none" {line(3.5)}/>')

BARREL = doc(64, 100,
    '<ellipse cx="24" cy="78" rx="26" ry="12" fill="#a59570"/>'
    '<clipPath id="bar"><path d="M7 24 L7 68 Q7 78 29 78 Q51 78 51 68 L51 24 Z"/></clipPath>'
    '<path d="M7 24 L7 68 Q7 78 29 78 Q51 78 51 68 L51 24 Z" fill="#2491cf"/>'
    '<rect x="29" y="0" width="30" height="100" fill="#3aa0dc" clip-path="url(#bar)"/>'
    f'<path d="M7 24 L7 68 Q7 78 29 78 Q51 78 51 68 L51 24" fill="none" {line(3.4)}/>'
    f'<path d="M7 40 Q29 50 51 40 M7 55 Q29 65 51 55" fill="none" {line(3.4)}/>'
    '<clipPath id="bat"><ellipse cx="29" cy="24" rx="22" ry="10"/></clipPath>'
    '<ellipse cx="29" cy="24" rx="22" ry="10" fill="#2e9ad6"/>'
    '<rect x="29" y="0" width="30" height="40" fill="#3aa6e2" clip-path="url(#bat)"/>'
    f'<ellipse cx="29" cy="24" rx="22" ry="10" fill="none" {line(3.4)}/>')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    jobs = []
    for name, body, scale in (("hero", HERO, 3), ("skeleton", SKELETON, 3), ("tree", TREE, 2), ("barrel", BARREL, 3)):
        source = OUT / f"{name}.svg"
        source.write_text(body)
        jobs.append((source, OUT / f"{name}.png", scale))
    flat.rasterise(jobs)


if __name__ == "__main__":
    main()
