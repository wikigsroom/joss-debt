"""Package the user's four local tracks for offline native playback."""
from pathlib import Path
import hashlib, json, subprocess
ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path("C:/Users/carzy/Downloads/yourset-old")
OUT = ROOT / "game/assets/audio/yourset"

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    rows=[]
    for i,path in enumerate(sorted(SOURCE.glob('*.mp3')),1):
        target=OUT/f"track-{i:02d}.ogg"
        probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-of','json',str(path)]))['format']
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(path),'-map','0:a:0',
            '-af','loudnorm=I=-18:TP=-1.5:LRA=11','-ar','48000','-ac','2','-c:a','libvorbis','-q:a','5',
            '-metadata',f"title={probe.get('tags',{}).get('title',path.stem)}",str(target)],check=True)
        encoded=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-of','json',str(target)]))['format']
        rows.append(dict(id=f"yourset-{i:02d}",title=probe.get('tags',{}).get('title',path.stem),artist='Yourset',
            source_filename=path.name,source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
            path='res://assets/audio/yourset/'+target.name,sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
            duration=float(encoded['duration']),bytes=target.stat().st_size,loop=False))
        print('Packaged '+path.name,flush=True)
    assert len(rows)==4, 'Expected all four user-specified tracks'
    manifest=dict(version=1,mode='shuffle-bag',crossfade_seconds=1.2,prevent_adjacent_repeats=True,
        source='User-selected local Yourset collection',normalization='48 kHz stereo Vorbis, loudnorm -18 LUFS / -1.5 dBTP',tracks=rows)
    (ROOT/'game/data/music_playlist.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf8')
    (ROOT/'docs/incense-debt/reports/runtime/yourset-import.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf8')
if __name__=='__main__':main()
