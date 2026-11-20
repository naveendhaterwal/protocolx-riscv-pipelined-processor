#!/usr/bin/env python3
"""
Assemble the ProtocolX Phase I video from voice lines + rendered stills.

    python3 assemble.py --script script.json --voices voices --stills visuals/out --out protocolx_phase1.mp4

Inputs
  script.json      members -> lines (shot, sub, lt)  [see script.json]
  voices/          one WAV per line: <member>_<NN>.wav (NN = 01, 02, ... in script order)
  visuals/out/     1920x1080 PNG stills + lower_third_<member>.png overlays

How it works
  1. Each voice line is trimmed of leading/trailing silence and its length measured.
  2. The line's subtitle is split into chunks of at most two lines; each chunk is
     shown for a share of the line's time proportional to its length.
  3. Every chunk becomes one composited frame (slide scaled into the top area,
     subtitle in a bottom band, name card on a member's first line).
  4. ffmpeg's concat demuxer turns the frames + durations into video; the voice
     lines + pauses are concatenated into one track, loudness-normalised, muxed.
Video timing is derived from the audio, so pictures can never drift from speech.
"""
import argparse
import json
import os
import shutil
import subprocess
import tempfile
import textwrap

from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
SCALE = 0.875                      # slide area 1680x945, subtitle band below it
SW, SH = int(W * SCALE), int(H * SCALE)
SX, SY = (W - SW) // 2, 0
BAND_TOP = SH
BG = (11, 17, 32)
SUB_FG, SUB_MAX_CHARS = (241, 245, 249), 72
FPS = 30
LEAD_IN, TAIL = 0.6, 1.8           # seconds of picture before first / after last line


def font(size, bold=True):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            return ImageFont.truetype(c, size, index=1 if (c.endswith(".ttc") and bold) else 0)
    return ImageFont.load_default()


SUB_FONT = font(36)


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         check=True, capture_output=True, text=True).stdout
    return float(out.strip())


def trim_silence(src, dst):
    # Remove leading and trailing silence (below -45 dB), keep 60 ms of room tone at each end.
    f = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.06,areverse,"
         "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.06,areverse")
    run(["ffmpeg", "-y", "-i", src, "-af", f, "-ar", "24000", "-ac", "1", dst])


def silence(dst, seconds):
    run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", f"{seconds:.3f}", dst])


def sub_chunks(text):
    """Split a subtitle into chunks of <= 2 wrapped lines."""
    lines = textwrap.wrap(text, SUB_MAX_CHARS)
    return ["\n".join(lines[i:i + 2]) for i in range(0, len(lines), 2)] or [""]


def compose(still_path, sub, lower_third=None):
    canvas = Image.new("RGB", (W, H), BG)
    slide = Image.open(still_path).convert("RGB").resize((SW, SH), Image.LANCZOS)
    canvas.paste(slide, (SX, SY))
    if lower_third:
        lt = Image.open(lower_third).convert("RGBA").resize((SW, SH), Image.LANCZOS)
        canvas.paste(lt, (SX, SY), lt)
    d = ImageDraw.Draw(canvas)
    d.line([(0, BAND_TOP), (W, BAND_TOP)], fill=(36, 50, 77), width=2)
    if sub:
        box = d.multiline_textbbox((0, 0), sub, font=SUB_FONT, spacing=10, align="center")
        tw, th = box[2] - box[0], box[3] - box[1]
        x = (W - tw) // 2
        y = BAND_TOP + (H - BAND_TOP - th) // 2 - box[1]
        d.multiline_text((x, y), sub, font=SUB_FONT, fill=SUB_FG, spacing=10, align="center")
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--script", default="script.json")
    ap.add_argument("--voices", default="voices")
    ap.add_argument("--stills", default="visuals/out")
    ap.add_argument("--out", default="protocolx_phase1.mp4")
    ap.add_argument("--members", default="", help="comma list to build only some members (preview)")
    a = ap.parse_args()

    sc = json.load(open(a.script))
    only = set(filter(None, a.members.split(",")))
    work = tempfile.mkdtemp(prefix="assemble_")
    frames, audio_parts, t = [], [], 0.0
    report = []

    def hold(img_path, seconds):
        frames.append((img_path, seconds))

    first_img = None
    members = [m for m in sc["members"] if not only or m["name"] in only]
    for mi, m in enumerate(members):
        for li, line in enumerate(m["lines"], 1):
            src = os.path.join(a.voices, f"{m['name']}_{li:02d}.wav")
            if not os.path.exists(src):
                raise SystemExit(f"missing voice line: {src}")
            clip = os.path.join(work, f"{m['name']}_{li:02d}.wav")
            trim_silence(src, clip)
            dur = duration(clip)
            still = os.path.join(a.stills, line["shot"] + ".png")
            lt = os.path.join(a.stills, f"lower_third_{m['name']}.png") if line.get("lt") else None
            chunks = sub_chunks(line["sub"])
            total_chars = sum(len(c) for c in chunks)
            for ci, c in enumerate(chunks):
                img = os.path.join(work, f"f_{len(frames):04d}.png")
                compose(still, c, lt).save(img)
                hold(img, dur * len(c) / total_chars)
                first_img = first_img or img
            audio_parts.append(clip)
            report.append((m["name"], li, t, dur, line["shot"]))
            t += dur
            last_line = li == len(m["lines"])
            gap = sc["pause_between_members"] if last_line else sc["pause_between_lines"]
            if not (last_line and mi == len(members) - 1):
                sil = os.path.join(work, f"sil_{len(audio_parts)}.wav")
                silence(sil, gap)
                audio_parts.append(sil)
                # during the pause keep the last chunk's picture, without subtitle
                img = os.path.join(work, f"f_{len(frames):04d}.png")
                compose(still, "", lt if not last_line else None).save(img)
                hold(img, gap)
                t += gap

    # lead-in (title, no subtitle) and tail (last picture, no subtitle)
    lead = os.path.join(work, "lead.png")
    compose(os.path.join(a.stills, members[0]["lines"][0]["shot"] + ".png"), "").save(lead)
    tail = os.path.join(work, "tail.png")
    compose(os.path.join(a.stills, members[-1]["lines"][-1]["shot"] + ".png"), "").save(tail)
    frames = [(lead, LEAD_IN)] + frames + [(tail, TAIL)]
    s0, s1 = os.path.join(work, "lead.wav"), os.path.join(work, "tail.wav")
    silence(s0, LEAD_IN)
    silence(s1, TAIL)
    audio_parts = [s0] + audio_parts + [s1]

    # audio: concatenate, then normalise to -16 LUFS (typical for online video)
    alist = os.path.join(work, "audio.txt")
    with open(alist, "w") as f:
        f.writelines(f"file '{p}'\n" for p in audio_parts)
    voice = os.path.join(work, "voice.wav")
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", alist, "-ar", "48000", "-ac", "1", voice])
    voice_n = os.path.join(work, "voice_norm.wav")
    run(["ffmpeg", "-y", "-i", voice, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "48000", voice_n])

    # video: still frames with exact durations (concat demuxer needs the last file repeated)
    vlist = os.path.join(work, "video.txt")
    with open(vlist, "w") as f:
        for p, d in frames:
            f.write(f"file '{p}'\nduration {d:.4f}\n")
        f.write(f"file '{frames[-1][0]}'\n")
    total = sum(d for _, d in frames)
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", vlist, "-i", voice_n,
         "-vf", f"fps={FPS},format=yuv420p,fade=t=in:st=0:d=0.4,fade=t=out:st={total-0.6:.2f}:d=0.6",
         "-c:v", "libx264", "-preset", "medium", "-tune", "stillimage", "-crf", "18",
         "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", a.out])

    print(f"\nWrote {a.out}  ({duration(a.out):.1f} s)")
    print(f"{'member':8} {'line':>4} {'start':>7} {'len':>5}  shot")
    for name, li, st, d, shot in report:
        print(f"{name:8} {li:>4} {st+LEAD_IN:7.1f} {d:5.1f}  {shot}")
    per = {}
    for name, _, st, d, _ in report:
        per.setdefault(name, [st, st + d])[1] = st + d
    for name, (s, e) in per.items():
        print(f"  {name:8} {s+LEAD_IN:6.1f}s – {e+LEAD_IN:6.1f}s  ({e-s:5.1f} s)")
    if duration(a.out) > 300:
        print("WARNING: longer than 5:00 — regenerate voices with a higher SPEED (e.g. 1.08).")
    shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
