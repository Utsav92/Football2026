#!/usr/bin/env python3
"""Assemble the FOOTBALL 2026 launch trailer: in-engine frames + PlayStation-style esports motion graphics (ffmpeg) + synthesised audio."""
import subprocess, os, sys
D = os.path.dirname(os.path.abspath(__file__)); os.chdir(D)
FONT = "/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf"; FONT2 = "/System/Library/Fonts/SFNS.ttf"
BLUE, CYAN, WHITE, RED = "0x0070D1", "0x00E5FF", "white", "0xFF2D55"
FPS = 30; NF = len([f for f in os.listdir("frames") if f.endswith(".png")]); DUR = NF / FPS
print("frames", NF, "duration", round(DUR, 2))

# ---------- still assets (slanted bars) ----------
def asset(name, w, h, rgb, alpha, slant=0.35):
    if os.path.exists(name): return
    subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", f"color=s={w}x{h}:c=black,format=rgba", "-vf",
        f"geq=r='{rgb[0]}':g='{rgb[1]}':b='{rgb[2]}':a='if(between(X,({h}-Y)*{slant},{w}-Y*{slant}),{alpha},0)'", "-frames:v", "1", name], check=True, capture_output=True)
asset("bar_blue.png", 1180, 130, ("0", "90+X*0.12", "230"), 255)
asset("bar_dark.png", 1000, 64, ("8", "12", "28"), 215)
asset("tag_dark.png", 520, 56, ("8", "12", "28"), 220, 0.3)

# ---------- filter graph builder ----------
G = []; cur = "g"; n = 0
def add(f):
    global cur, n; n += 1; out = f"s{n}"; G.append(f"[{cur}]{f}[{out}]"); cur = out
def ease(A, dur=0.4):   # 1 at start -> 0 after dur (cubic out)
    return f"pow(1-min(1,max(0,(t-{A})/{dur})),3)"
def txt(text, x, y, size, color, A, B, font=FONT, extra=""):
    add(f"drawtext=fontfile='{font}':text='{text}':fontsize={size}:fontcolor={color}:x='{x}':y='{y}':enable='between(t,{A},{B})':shadowcolor=black@0.5:shadowx=3:shadowy=3{extra}")
def flash(t0, a=0.55, d=0.07):
    add(f"drawbox=x=0:y=0:w=iw:h=ih:color=white@{a}:t=fill:enable='between(t,{t0},{t0+d})'")
    add(f"drawbox=x=0:y=0:w=iw:h=ih:color=white@{a*0.4}:t=fill:enable='between(t,{t0+d},{t0+2*d})'")
def grow_bar(x, y, w, h, color, A, steps=10, dt=0.03, B=None):
    for k in range(steps):
        add(f"drawbox=x={x}:y={y}:w={int(w*(k+1)/steps)}:h={h}:color={color}:t=fill:enable='between(t,{A+k*dt},{A+(k+1)*dt})'")
    add(f"drawbox=x={x}:y={y}:w={w}:h={h}:color={color}:t=fill:enable='between(t,{A+steps*dt},{B if B else A+99})'")

# grade: contrast, saturation, teal/orange split, vignette, grain
add("eq=contrast=1.14:saturation=1.28:brightness=-0.02:gamma=0.97")
add("colorbalance=rs=-0.04:bs=0.06:rm=0.0:bm=0.03:rh=0.06:bh=-0.05")
add("vignette=PI/5.2")
add("noise=alls=4:allf=t")

# the 3rd mosaic cut (broadcast cam) comes out washed by auto-exposure after the dark sideline cut: correct it
add("eq=contrast=1.4:brightness=-0.1:saturation=1.7:gamma=1.1:enable='between(t,34.5,34.85)'")
CUTS = [7.0, 11.0, 15.0, 18.5, 23.5, 27.1, 32.1, 39.3, 42.3, 47.3, 52.3]
for c in CUTS: flash(round(c - 0.03, 2))
for i in range(1, 6): flash(round(32.1 + 1.2 * i - 0.03, 2), a=0.4, d=0.05)

# --- bars: slanted lower-third banners (title, subtitle, start, end) ---
banners = [
    ("REAL MOTION CAPTURE", "MOCAP DRIVEN RUN  KICK  TACKLE", 11.3, 14.7),
    ("ELITE KEEPERS", "DIVES   CATCHES   PUNCHES", 15.3, 18.2),
    ("11 v 11  SMART AI", "TRAINED ON REAL TRACKING DATA", 18.8, 23.2),
    ("MOMENTS THAT LAST", "CELEBRATIONS   LIVE COMMENTARY", 29.3, 32.0),
    ("6 BROADCAST CAMERAS", "TELE   SIDELINE   STADIUM   HERO   ORBIT", 32.4, 38.9),
    ("PRO DEFENDING", "SLIDE   JOCKEY   SHIELD", 39.6, 42.1),
    ("LUMEN LIGHTING", "REAL TIME GLOBAL ILLUMINATION", 42.6, 46.9),
    ("YOUR SIDE  YOUR RULES", "SWITCH HOME OR AWAY MID MATCH", 47.7, 51.9),
]
BANNER_IN = []
for i, (t, s, A, B) in enumerate(banners):
    off = f"(-1300*{ease(A)}-1300*pow(min(1,max(0,(t-{B-0.3})/0.3)),3))"
    BANNER_IN.append((A, B, off, t, s))

# ---------- overlay pass for bars needs extra inputs; build after text so order stays simple ----------
def banner_text(A, B, off, t, s):
    txt(t, f"110+{off}", 818, 82, WHITE, A, B)
    txt(s, f"112+{off}", 905, 34, "0xC8E9FF", A, B)

# opening: black fade handled at the end; kicker + stacked title with chromatic slam
txt("A NEW ERA OF FOOTBALL", "(w-text_w)/2", 232, 44, CYAN, 0.7, 6.4, extra=":alpha='min(1,(t-0.7)/0.4)'")
for dx, col in ((-9, RED), (9, CYAN)):   # RGB split during the slam
    txt("FOOTBALL", f"(w-text_w)/2+{dx}-1500*{ease(1.0, 0.45)}", 285, 300, col + "@0.85", 1.0, 1.32)
    txt("2026", f"(w-text_w)/2+{dx}+1500*{ease(1.15, 0.45)}", 575, 300, col + "@0.85", 1.15, 1.47)
txt("FOOTBALL", f"(w-text_w)/2-1500*{ease(1.0, 0.45)}", 285, 300, WHITE, 1.0, 6.4, extra=":alpha='if(gt(t,6.0),max(0,1-(t-6.0)/0.4),1)'")
txt("2026", f"(w-text_w)/2+1500*{ease(1.15, 0.45)}", 575, 300, CYAN, 1.15, 6.4, extra=":alpha='if(gt(t,6.0),max(0,1-(t-6.0)/0.4),1)'")
grow_bar(660, 560, 600, 8, CYAN, 1.7, B=6.4)
txt("P L A Y   T H E   M O M E N T", "(w-text_w)/2", 900, 40, WHITE, 2.7, 6.4, font=FONT2, extra=":alpha='min(1,(t-2.7)/0.5)'")

# LIVE tag + series marker through the gameplay section
add(f"drawbox=x=1480:y=44:w=18:h=18:color={RED}:t=fill:enable='between(t,7.2,52.2)*lt(mod(t,1),0.65)'")
txt("LIVE", "1510", 36, 38, WHITE, 7.2, 52.2)
txt("FOOTBALL 2026", "1620", 36, 38, CYAN, 7.2, 52.2)

# AI stat counters (26.9-31.3)
txt("%{eif\\:min(11\\,trunc((t-19.2)*14))\\:d}", "1330", 650, 210, WHITE, 19.2, 23.2)
txt("v 11", "1500", 755, 90, CYAN, 19.4, 23.2)
txt("120 HZ SIMULATION", "1330", 870, 40, "0xC8E9FF", 19.7, 23.2)

# camera tags in the mosaic
cams = ["TELE", "SIDELINE", "BROADCAST", "STADIUM", "HERO", "ORBIT"]
for i, nm in enumerate(cams):
    A = 32.1 + 1.2 * i; B = A + 1.2
    add(f"drawbox=x=90:y=955:w=18:h=72:color={CYAN}:t=fill:enable='between(t,{A},{B})'")
    txt(f"CAM 0{i+1}", "125", 950, 40, CYAN, A, B)
    txt(nm, "125", 984, 48, WHITE, A, B)

# GOAL slam (ball crosses the line at ~35.55 s)
G0 = 27.55
add(f"drawbox=x=0:y=0:w=iw:h=ih:color=white@0.85:t=fill:enable='between(t,{G0},{G0+0.06})'")
add(f"drawbox=x=0:y=0:w=iw:h=ih:color=white@0.35:t=fill:enable='between(t,{G0+0.06},{G0+0.14})'")
for dx, col in ((-14, RED), (14, CYAN)):
    txt("GOAL", f"(w-text_w)/2+{dx}", "(h-text_h)/2-120", 520, col + "@0.9", G0, G0 + 0.3)
txt("GOAL", "(w-text_w)/2", "(h-text_h)/2-120", 520, WHITE, G0, G0 + 1.7, extra=f":alpha='if(gt(t,{G0+1.3}),max(0,1-(t-{G0+1.3})/0.4),1)'")

# end card
txt("FOOTBALL 2026", "(w-text_w)/2", "(h-text_h)/2-60", 230, WHITE, 53.6, 58.3, extra=":alpha='min(1,(t-53.6)/0.5)'")
grow_bar(710, 705, 500, 8, CYAN, 54.4, B=58.3)
txt("COMING SOON TO MAC", "(w-text_w)/2", 760, 42, "0xC8E9FF", 55.2, 58.3, font=FONT2, extra=":alpha='min(1,(t-55.2)/0.5)'")
add(f"fade=t=in:st=0:d=0.6,fade=t=out:st={round(DUR-0.9,2)}:d=0.9")

# ---------- banners last (they need the bar inputs): overlay bar -> text ----------
bar_labels = []
for (A, B, off, t, s) in BANNER_IN:
    n += 1; out = f"s{n}"; G.append(f"[{cur}][1:v]overlay=x='60+{off}':y=770:enable='between(t,{A},{B})':eval=frame[{out}]"); cur = out
    banner_text(A, B, off, t, s)
# menu-section tag
n += 1; out = f"s{n}"; G.append(f"[{cur}][2:v]overlay=x='1380':y=30:enable='between(t,7.2,52.2)'[{out}]"); cur = out
# (tag_dark sits under the LIVE text drawn earlier, so re-draw the text on top)
add(f"drawbox=x=1480:y=44:w=18:h=18:color={RED}:t=fill:enable='between(t,7.2,52.2)*lt(mod(t,1),0.65)'")
txt("LIVE", "1510", 36, 38, WHITE, 7.2, 52.2); txt("FOOTBALL 2026", "1620", 36, 38, CYAN, 7.2, 52.2)

G.append(f"[{cur}]format=yuv420p[vout]")
open("graph.txt", "w").write(";\n".join(G))
cmd = ["ffmpeg", "-y", "-framerate", str(FPS), "-i", "frames/f%05d.png", "-i", "bar_blue.png", "-i", "tag_dark.png", "-i", "audio.wav",
       "-/filter_complex", "graph.txt", "-map", "[vout]", "-map", "3:a", "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p",
       "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", "-shortest", "-movflags", "+faststart", "Football2026_Trailer.mp4"]
if "--preview" in sys.argv: cmd = [c if c != "frames/f%05d.png" else "frames/f%05d.png" for c in cmd]; cmd[cmd.index("-crf") + 1] = "26"; cmd[cmd.index("-preset") + 1] = "veryfast"; cmd[-1] = "preview.mp4"
subprocess.run(cmd, check=True)
print("done")
