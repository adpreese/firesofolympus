# Egg-and-dart nine-slice frame for the playmat -> assets/images/table/frame.svg
# Usage: python3 tools/make_playmat_frame.py [repeat_px]  (FoUI.Playmat draws it).
# B = band depth, L = one egg+dart repeat.
import sys
BAND="#C3A576"; DEEP="#B39567"; EGG="#D9C39D"; SHELL="#C8AC7F"; DART="#A5875A"  # one shade below DEEP
B=28; L=int(sys.argv[1]) if len(sys.argv)>1 else 24; S=2*B+L; c=L/2
def shell(top):  # U-shaped shell (fill + open stroke) and egg, centred on x=c; legs start at y=top
    d=f"M{c-8} {top}V14A8 8 0 0 0 {c+8} 14V{top}"
    return (f'<path d="{d}Z" fill="{SHELL}"/><path d="{d}" fill="none" stroke="{DEEP}" stroke-width="2"/>'
            f'<ellipse cx="{c}" cy="11.5" rx="5" ry="8.5" fill="{EGG}"/>')
def strip():  # outer edge at y=0, eggs hang toward the mat
    return (f'<rect width="{L}" height="{B}" fill="{BAND}"/>'
            f'<rect width="{L}" height="3" fill="{DEEP}"/><rect y="{B-2}" width="{L}" height="2" fill="{DEEP}"/>'
            # dart: a 3 px brush stroke that tapers to a point, split across the tile seam
            f'<path d="M0 3H1.5C1.75 9 1.35 15 0 21Z" fill="{DART}"/><path d="M{L} 3H{L-1.5}C{L-1.75} 9 {L-1.35} 15 {L} 21Z" fill="{DART}"/>'
            + shell(3))
def corner():  # outer edges top and left; egg at 45 deg, shell legs run into the frame lines
    return (f'<rect width="{B}" height="{B}" fill="{BAND}"/>'
            f'<g transform="translate(14 14) rotate(-45) translate({-c} -10.5)">{shell(-20)}</g>'
            f'<rect width="{B}" height="3" fill="{DEEP}"/><rect width="3" height="{B}" fill="{DEEP}"/>'
            f'<rect x="{B-2}" y="{B-2}" width="2" height="2" fill="{DEEP}"/>')
edges=[f'translate({B},0)', f'translate({B+L},{S}) rotate(180)', f'translate(0,{B+L}) rotate(-90)', f'translate({S},{B}) rotate(90)']
corners=['translate(0,0)', f'translate({S},0) rotate(90)', f'translate({S},{S}) rotate(180)', f'translate(0,{S}) rotate(-90)']
g="".join(f'<g transform="{t}">{strip()}</g>' for t in edges)+"".join(f'<g transform="{t}">{corner()}</g>' for t in corners)
open("assets/images/table/frame.svg","w").write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">\n{g}\n</svg>\n')
