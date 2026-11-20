# Generate every voice line, verify it, retry if needed
import os, json, re, difflib, subprocess
import numpy as np
from f5_tts.api import F5TTS
from faster_whisper import WhisperModel
from num2words import num2words

# F5-TTS clips references to 12 s; keep Shagun's ref under that with a transcript that matches exactly.
if float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0','ref/shagun.wav'],
                        capture_output=True, text=True).stdout) > 11.5:
    subprocess.run(['ffmpeg','-v','error','-y','-i','ref/shagun.wav','-t','7.6','/tmp/s.wav'], check=True)
    os.replace('/tmp/s.wav', 'ref/shagun.wav')
    open('ref/shagun.txt','w').write('Hello everyone, we are presenting our project on credit risk scoring and loan default prediction.')

script = json.load(open('script.json'))
tts = F5TTS()

def load16k(path):
    # Decode with ffmpeg (not PyAV, whose installed version breaks faster-whisper's file loader).
    raw = subprocess.run(['ffmpeg','-v','error','-i',path,'-f','s16le','-ac','1','-ar','16000','-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.int16).astype(np.float32) / 32768

try:
    asr = WhisperModel('small.en', device='cuda', compute_type='float16')
    list(asr.transcribe(load16k('ref/aditya.wav'))[0])  # fail fast if cuDNN is missing
except Exception as e:
    print('Whisper on GPU failed, using CPU:', e)
    asr = WhisperModel('small.en', device='cpu', compute_type='int8')
os.makedirs('voices', exist_ok=True)

def letters(s):
    s = re.sub(r'\d+(\.\d+)?', lambda m: ' ' + num2words(float(m.group()) if '.' in m.group() else int(m.group())) + ' ', s)
    return re.sub(r'[^a-z]', '', s.lower())

def heard(path):
    segs, _ = asr.transcribe(load16k(path), beam_size=5)
    return ' '.join(s.text.strip() for s in segs)

log = []
for m in script['members']:
    ref = f"ref/{m['name']}.wav"
    ref_text = open(f"ref/{m['name']}.txt").read().strip() + ' '
    for i, line in enumerate(m['lines'], 1):
        out = f"voices/{m['name']}_{i:02d}.wav"
        best = (-1, None)
        for t in range(MAX_TRIES):
            tmp = f"/tmp/try_{t}.wav"
            tts.infer(ref_file=ref, ref_text=ref_text, gen_text=line['tts'], file_wave=tmp,
                      seed=1000 + 17 * t + i, speed=SPEED, remove_silence=False, show_info=lambda *a, **k: None)
            h = heard(tmp)
            score = difflib.SequenceMatcher(None, letters(line['tts']), letters(h)).ratio()
            if score > best[0]:
                best = (score, h)
                os.replace(tmp, out)
            if score >= MIN_MATCH:
                break
        log.append((m['name'], i, round(best[0], 2), best[1]))
        flag = '' if best[0] >= MIN_MATCH else '   <-- CHECK THIS LINE'
        print(f"{m['name']:7} {i:02d}  match={best[0]:.2f}{flag}\n        heard: {best[1]}")
bad = [l for l in log if l[2] < MIN_MATCH]
print('\nAll lines matched.' if not bad else f'\n{len(bad)} line(s) below {MIN_MATCH}: listen to them below.')
