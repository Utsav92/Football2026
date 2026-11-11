#!/usr/bin/env python3
"""Synthesised trailer score + voice (macOS `say`) -> audio.wav. No samples, no third-party music."""
import subprocess, os, sys
D = os.path.dirname(os.path.abspath(__file__)); os.chdir(D)
DUR = 58.3; GOAL = 27.55
def run(*a): subprocess.run(a, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def syn(name, expr, dur=DUR, post=""):
    run("ffmpeg", "-y", "-f", "lavfi", "-i", f"aevalsrc='{expr}':s=44100:d={dur}", *(["-af", post] if post else []), f"a_{name}.wav")

# 120 bpm grid; the music enters at the first cut (7 s)
ON = "gt(t,6.6)"
syn("kick", f"{ON}*0.95*sin(2*PI*(42+130*exp(-28*mod(t,0.5)))*mod(t,0.5))*exp(-8*mod(t,0.5))", post="lowpass=f=180")
syn("snare", f"{ON}*gte(mod(t,1),0.5)*lt(mod(t,1),0.52)*0+{ON}*(random(3)-0.5)*0.5*exp(-18*mod(t+0.5,1))", post="highpass=f=1500,lowpass=f=9000")
syn("hat", f"{ON}*(random(1)-0.5)*0.3*exp(-70*mod(t+0.25,0.25))", post="highpass=f=7000")
syn("bass", f"{ON}*0.42*sin(2*PI*if(lt(mod(floor(t/2),4),2),55,if(eq(mod(floor(t/2),4),2),49,65.4))*t)*(0.65+0.35*sin(2*PI*2*t))", post="lowpass=f=240")
# arpeggio (A minor feel): semitone offsets over a 16th-note grid
N = [0, 7, 12, 15, 12, 7, 15, 19]
sel = "0"
for i, n in enumerate(N): sel = f"if(eq(mod(floor(t*8),8),{i}),{n},{sel})"
syn("arp", f"{ON}*0.18*(sin(2*PI*220*pow(2,({sel})/12)*t)+0.4*sin(4*PI*220*pow(2,({sel})/12)*t))*exp(-5*mod(t,0.125))", post="lowpass=f=5000,aecho=0.8:0.5:240:0.3")
# intro riser (0-7 s) and pre-goal tension riser
syn("riser", f"(random(5)-0.5)*0.5*pow(t/7,3)*lt(t,7)+0.12*sin(2*PI*(80+400*pow(t/7,3))*t)*pow(t/7,2)*lt(t,7)", post="highpass=f=300")
syn("tension", f"gt(t,{GOAL-2.2})*lt(t,{GOAL})*((random(8)-0.5)*0.7*pow((t-{GOAL-2.2})/2.2,2))", post="highpass=f=800")
# goal impact + crowd swell
syn("boom", f"gt(t,{GOAL})*sin(2*PI*(38+60*exp(-6*(t-{GOAL})))*(t-{GOAL}))*exp(-2.2*(t-{GOAL}))*0.95", post="lowpass=f=160")
syn("crowd", f"gt(t,{GOAL})*lt(t,{GOAL+6})*(random(9)-0.5)*0.55*min(1,(t-{GOAL})*3)*exp(-0.35*(t-{GOAL}))", post="lowpass=f=2400,highpass=f=250")
# outro sting
syn("sting", "gt(t,53.3)*lt(t,58.3)*(0.5*sin(2*PI*110*t)+0.3*sin(2*PI*165*t)+0.2*sin(2*PI*220*t))*exp(-0.5*(t-53.3))*0.35", post="lowpass=f=1800,aecho=0.8:0.6:420:0.35")

# Voice-over + goal call (Mac system voice). Delayed into place with adelay.
def say(name, text):
    run("say", "-v", "Daniel", "-o", f"v_{name}.aiff", text); run("ffmpeg", "-y", "-i", f"v_{name}.aiff", "-ar", "44100", "-ac", "2", f"v_{name}.wav")
say("a", "[[rate 150]] [[pbas 28]] This is football.")
say("b", "[[rate 140]] [[pbas 26]] Football. Twenty twenty six. [[slnc 250]] Play the moment.")
say("goal", "[[rate 165]] [[pbas +10]] Goal! [[slnc 150]] What a finish!")

inputs = [f"a_{n}.wav" for n in ("kick", "snare", "hat", "bass", "arp", "riser", "tension", "boom", "crowd", "sting")]
vo = [("v_a.wav", 1.5, 1.0), ("v_goal.wav", GOAL + 0.15, 1.1), ("v_b.wav", 54.4, 1.0)]
cmd = ["ffmpeg", "-y"]
for f in inputs: cmd += ["-i", f]
for f, _, _ in vo: cmd += ["-i", f]
vol = {"kick": 1.0, "snare": 0.7, "hat": 0.6, "bass": 0.9, "arp": 0.8, "riser": 0.9, "tension": 0.8, "boom": 1.0, "crowd": 0.9, "sting": 0.9}
parts = [f"[{i}:a]volume={vol[n]}[m{i}]" for i, n in enumerate(("kick", "snare", "hat", "bass", "arp", "riser", "tension", "boom", "crowd", "sting"))]
for j, (f, t, v) in enumerate(vo):
    i = len(inputs) + j; parts.append(f"[{i}:a]volume={v},adelay={int(t*1000)}|{int(t*1000)}[m{i}]")
mix = "".join(f"[m{i}]" for i in range(len(inputs) + len(vo)))
parts.append(f"{mix}amix=inputs={len(inputs)+len(vo)}:normalize=0,alimiter=limit=0.95,afade=t=in:d=0.4,afade=t=out:st={DUR-1.6}:d=1.6,loudnorm=I=-15:TP=-1.5[out]")
cmd += ["-filter_complex", ";".join(parts), "-map", "[out]", "-t", str(DUR), "audio.wav"]
run(*cmd); print("audio.wav ok")
