"""Build the project's layered, deterministic sound-effect library.

The game has a paper, copper and ember identity. Each gameplay family is
therefore authored as a short layered gesture rather than a single oscillator:
an attack has a readable transient, a material body and a small tail; impacts
have a low body plus a paper/copper tick; player damage has a distinct vocal
noise band and a low warning swell. Three deterministic pitch/length variants
are emitted for every family so repeated actions do not sound machine-gunned.
The v3 pass adds band-limited material noise, controlled sub drops and delayed
secondary transients so high-density combat remains punchy without clipping.
"""
from pathlib import Path
import json
import wave
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/audio"
RATE = 48000


def save(name: str, data: np.ndarray, family: str, design: str, manifest: list) -> dict:
    data = np.asarray(data, dtype=float)
    if not len(data):
        data = np.zeros(round(.02 * RATE))
    peak = float(np.max(np.abs(data)))
    if peak > .88:
        data *= .88 / peak
    path = OUT / (name + ".wav")
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes((np.clip(data, -.99, .99) * 32767).astype("<i2").tobytes())
    item = {
        "id": name,
        "file": "game/assets/audio/" + name + ".wav",
        "sample_rate": RATE,
        "channels": 1,
        "duration": len(data) / RATE,
        "peak": min(peak, .88),
        "family": family,
        "design": design,
        "source": "original deterministic layered synthesis v3",
    }
    manifest.append(item)
    return item


def time_axis(duration: float) -> np.ndarray:
    return np.arange(max(1, round(duration * RATE))) / RATE


def fade(data: np.ndarray, attack: float = .002, release: float = .035) -> np.ndarray:
    out = np.asarray(data, dtype=float).copy()
    a = min(len(out), max(1, round(attack * RATE)))
    r = min(len(out), max(1, round(release * RATE)))
    out[:a] *= np.linspace(0, 1, a)
    out[-r:] *= np.linspace(1, 0, r)
    return out


def tone(duration: float, frequency: float, decay: float = 8.0, level: float = 1.0,
         bend: float = 0.0, wobble: float = 0.0) -> np.ndarray:
    t = time_axis(duration)
    phase = 2 * np.pi * (frequency * t + bend * frequency * t * t / max(duration, .001))
    if wobble:
        phase += wobble * np.sin(2 * np.pi * 5.2 * t)
    signal = np.sin(phase) + .24 * np.sin(phase * 2.01) + .08 * np.sin(phase * 3.98)
    return fade(signal * np.exp(-t * decay) * level, .001, min(.06, duration * .3))


def sweep(duration: float, start: float, end: float, decay: float = 8.0, level: float = 1.0) -> np.ndarray:
    t = time_axis(duration)
    phase = 2 * np.pi * (start * t + (end - start) * t * t / max(duration * 2, .001))
    signal = np.sin(phase) + .2 * np.sin(phase * 2.02)
    return fade(signal * np.exp(-t * decay) * level, .001, min(.06, duration * .25))


def noise(duration: float, level: float = 1.0, smooth: int = 1, seed: int = 0) -> np.ndarray:
    local = np.random.default_rng(91377 + seed)
    data = local.normal(0, 1, len(time_axis(duration)))
    if smooth > 1:
        kernel = np.ones(smooth) / smooth
        data = np.convolve(data, kernel, mode="same")
    return data * level


def band_noise(duration: float, low: float, high: float, level: float = 1.0, seed: int = 0) -> np.ndarray:
    """Deterministic filtered noise for paper air, grit and impact debris."""
    high = min(high, RATE * .47)
    low = max(20.0, min(low, high - 30.0))
    raw = noise(duration, 1.0, 1, seed)
    filtered = sosfilt(butter(2, [low, high], fs=RATE, btype="bandpass", output="sos"), raw)
    peak = max(1e-8, float(np.max(np.abs(filtered))))
    return filtered / peak * level


def click(duration: float, frequency: float, level: float = 1.0) -> np.ndarray:
    t = time_axis(duration)
    return fade((np.sin(2 * np.pi * frequency * t) + .16 * noise(duration, 1, 3, round(frequency))) *
                np.exp(-t * 70) * level, .0005, .025)


def body(duration: float, root: float, level: float = 1.0, decay: float = 8.0) -> np.ndarray:
    t = time_axis(duration)
    signal = (np.sin(2 * np.pi * root * t) + .42 * np.sin(2 * np.pi * root * 1.51 * t) +
              .16 * np.sin(2 * np.pi * root * 2.96 * t))
    return fade(signal * np.exp(-t * decay) * level, .001, min(.12, duration * .35))


def sub_drop(duration: float, start: float, end: float, level: float = 1.0) -> np.ndarray:
    """A short controlled low-frequency drop that gives heavy hits weight."""
    t = time_axis(duration)
    phase = 2 * np.pi * (start * t + (end - start) * t * t / max(duration * 2, .001))
    envelope = np.minimum(t / .003, 1.0) * np.exp(-t * 7.0)
    return fade(np.sin(phase) * envelope * level, .001, min(.16, duration * .3))


def ping(duration: float, root: float, level: float = 1.0) -> np.ndarray:
    """Copper/jade transient with inharmonic partials and a short tail."""
    t = time_axis(duration)
    signal = (np.sin(2 * np.pi * root * t) + .42 * np.sin(2 * np.pi * root * 2.37 * t) +
              .18 * np.sin(2 * np.pi * root * 4.11 * t))
    return fade(signal * np.exp(-t * 13.0) * level, .0007, min(.16, duration * .3))


def delayed(data: np.ndarray, seconds: float) -> np.ndarray:
    offset = round(seconds * RATE)
    return np.concatenate([np.zeros(offset), np.asarray(data, dtype=float)])


def paper_tail(duration: float, level: float = 1.0, seed: int = 0) -> np.ndarray:
    t = time_axis(duration)
    air = noise(duration, level, 18, seed)
    crack = noise(duration, level * .32, 2, seed + 41)
    envelope = np.exp(-t * 14) * (0.8 + .2 * np.sin(2 * np.pi * 7 * t))
    return fade((air + crack) * envelope, .001, min(.12, duration * .35))


def metal_tail(duration: float, root: float, level: float = 1.0) -> np.ndarray:
    t = time_axis(duration)
    partials = (np.sin(2 * np.pi * root * t) + .55 * np.sin(2 * np.pi * root * 2.41 * t) +
                .24 * np.sin(2 * np.pi * root * 3.76 * t))
    return fade(partials * np.exp(-t * 5.4) * level, .001, min(.2, duration * .35))


def mix(*parts: np.ndarray) -> np.ndarray:
    length = max(len(part) for part in parts)
    result = np.zeros(length)
    for part in parts:
        result[:len(part)] += part
    return result


def variant_data(data: np.ndarray, index: int) -> np.ndarray:
    if index == 0:
        return data
    factor = [.965, 1.038][index - 1]
    samples = np.interp(np.arange(0, max(1, len(data) - 1), factor), np.arange(len(data)), data)
    if index == 2:
        samples = np.concatenate([samples, np.zeros(round(.006 * RATE))])
    return fade(samples, .001, .035)


def spec_library() -> dict:
    return {
        "shot": ("attack", "light paper projectile with snap, air and jade edge", mix(sweep(.11, 980, 2100, 18, .28), click(.09, 3200, .16), band_noise(.15, 1800, 7600, .10, 1), paper_tail(.15, .12, 1))),
        "shot_melee": ("attack", "brush slash with paper whoosh, copper edge and snap", mix(sweep(.20, 180, 680, 10, .25), band_noise(.25, 500, 2600, .19, 2), paper_tail(.25, .30, 2), metal_tail(.16, 220, .11), ping(.18, 280, .08))),
        "shot_ray": ("attack", "continuous jade ray with ignition, shimmer and air", mix(sweep(.42, 170, 920, 4, .18), tone(.48, 1180, 3.4, .10, wobble=.55), band_noise(.42, 700, 4200, .055, 3), ping(.16, 1760, .08))),
        "shot_heavy": ("attack", "charged or explosive release with ember sub, crack and debris", mix(sub_drop(.34, 110, 48, .30), body(.34, 78, .42, 5.5), sweep(.24, 210, 72, 6, .25), click(.16, 1750, .18), band_noise(.36, 120, 2400, .12, 4), paper_tail(.36, .14, 4))),
        "shot_controlled": ("attack", "guided paper mote with glassy pitch, flutter and jade ping", mix(sweep(.22, 380, 1320, 9, .23), tone(.32, 1047, 7, .13, wobble=.7), band_noise(.24, 900, 5200, .07, 5), paper_tail(.24, .08, 5), ping(.18, 1047, .08))),
        "hit": ("impact", "light warm-gold hit with paper tick, transient and grit", mix(body(.18, 138, .30, 22), click(.11, 1650, .30), band_noise(.18, 900, 5600, .13, 11), paper_tail(.18, .18, 11))),
        "hit_melee": ("impact", "melee thump, copper scrape and close debris", mix(body(.22, 102, .38, 15), metal_tail(.28, 315, .16), band_noise(.22, 180, 2800, .14, 12), paper_tail(.18, .10, 12), ping(.20, 410, .09))),
        "hit_heavy": ("impact", "heavy detonation with sub slam, mid crack and debris tail", mix(sub_drop(.42, 86, 42, .34), body(.42, 64, .54, 6.5), body(.20, 180, .22, 14), click(.16, 760, .26), band_noise(.42, 90, 3100, .22, 13), paper_tail(.42, .25, 13))),
        "hit_crit": ("impact", "critical hit with bright double chime, transient and spark", mix(body(.20, 172, .30, 16), metal_tail(.38, 640, .18), tone(.30, 1245, 8, .13), ping(.25, 1900, .16), click(.08, 2600, .14))),
        "hit_armor": ("impact", "armor contact with hard copper ring, plate knock and grit", mix(metal_tail(.34, 248, .38), click(.15, 1480, .24), body(.18, 92, .25, 20), ping(.34, 520, .18), band_noise(.26, 240, 2100, .10, 14))),
        "hit_chain": ("impact", "chain proc with two linked ticks and metallic recoil", mix(click(.12, 440, .25), delayed(click(.20, 880, .20), .055), metal_tail(.42, 520, .12), ping(.34, 720, .10))),
        "hurt": ("hurt", "short paper-body recoil with vocal grit and low thump", mix(body(.34, 92, .42, 9), band_noise(.32, 180, 1150, .19, 21), sweep(.25, 410, 120, 8, .12), paper_tail(.32, .12, 22))),
        "hurt_heavy": ("hurt", "heavy incoming damage with low warning swell, crack and sub", mix(sub_drop(.52, 72, 38, .24), body(.52, 58, .55, 5.5), band_noise(.48, 130, 1800, .28, 22), sweep(.42, 760, 110, 5, .20), paper_tail(.48, .14, 24))),
        "hurt_debt": ("hurt", "debt fire sting with metallic after-ring, ember noise and drop", mix(sweep(.30, 420, 92, 8, .30), metal_tail(.55, 176, .20), ping(.46, 340, .13), band_noise(.32, 420, 3200, .12, 23), paper_tail(.32, .12, 23))),
        "skill": ("ability", "ember skill ignition and resonant flare", mix(sweep(.44, 90, 520, 4.5, .32), tone(.62, 784, 5, .16, wobble=.45), paper_tail(.52, .18, 31))),
        "dash": ("movement", "paper fan whoosh", mix(sweep(.24, 1600, 220, 13, .25), paper_tail(.27, .36, 32))),
        "pickup": ("reward", "small jade pickup sparkle", mix(tone(.34, 880, 11, .18), tone(.38, 1320, 14, .10), click(.13, 2600, .10))),
        "bell": ("ritual", "copper bell with paper resonance", mix(metal_tail(1.25, 523.25, .26), tone(1.0, 789, 4.8, .09), paper_tail(1.1, .05, 41))),
        "clear": ("ritual", "room clear rising three-note cadence", mix(tone(.92, 440, 4.8, .16), tone(1.15, 554.37, 4.5, .12), tone(1.40, 659.25, 4.0, .10), paper_tail(1.4, .06, 42))),
        "mark": ("status", "ember mark pin and tail", mix(click(.14, 1240, .20), tone(.25, 620, 12, .16), paper_tail(.2, .08, 43))),
        "chain": ("status", "linked debt chain snap", mix(metal_tail(.32, 391, .25), click(.15, 970, .22), paper_tail(.28, .14, 44))),
        "death": ("death", "enemy collapse with ember fall", mix(body(.48, 72, .40, 6.5), sweep(.52, 540, 60, 7, .20), paper_tail(.58, .20, 45))),
        "warning": ("warning", "danger pulse with paper tick", mix(sweep(.42, 220, 1046, 4.8, .22), tone(.38, 880, 5, .12, wobble=.3), click(.10, 2200, .14))),
        "contract": ("ui", "debt contract stamp and copper ring", mix(body(.32, 164, .28, 9), metal_tail(.55, 330, .18), click(.13, 1600, .16))),
        "repay": ("ui", "repayment release with descending chime", mix(tone(.52, 660, 5, .16), tone(.68, 523.25, 5, .14), metal_tail(.72, 392, .10))),
        "menu": ("ui", "rounded menu tick", mix(click(.11, 610, .16), paper_tail(.12, .05, 51))),
        "armor": ("defense", "armor break copper plate", mix(metal_tail(.30, 293, .40), body(.32, 88, .24, 10), click(.12, 1380, .16))),
        "deflect": ("defense", "projectile deflect bright ring", mix(metal_tail(.30, 740, .28), click(.10, 2100, .20), paper_tail(.23, .09, 61))),
        "burst": ("impact", "small burst of ash and paper", mix(body(.24, 110, .28, 12), paper_tail(.28, .35, 62), click(.09, 1260, .12))),
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    previous = {}
    manifest_path = OUT / "manifest.json"
    if manifest_path.exists():
        try:
            previous = json.loads(manifest_path.read_text("utf8"))
        except json.JSONDecodeError:
            previous = {}
    manifest = []
    for group, (family, design, data) in spec_library().items():
        for index in range(3):
            name = group if index == 0 else group + "_" + str(index)
            save(name, variant_data(data, index), family, design, manifest)
    for item in previous.get("assets", []):
        if item.get("file", "").endswith(".ogg") and (ROOT / item["file"]).is_file():
            manifest.append(item)
    payload = {"sample_rate": RATE, "license": "project original; external CC0 texture provenance is recorded separately",
               "revision": "layered-sfx-v3", "assets": manifest}
    if previous.get("scores"):
        payload["scores"] = previous["scores"]
    manifest_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", "utf8")
    wav_count = len([item for item in manifest if item["file"].endswith(".wav")])
    print("Created %d layered sound assets (%d families × 3 variants); existing music stems preserved." %
          (wav_count, len(spec_library())))


if __name__ == "__main__":
    main()

