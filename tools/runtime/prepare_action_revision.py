"""Prepare reference-bound independent pose sheets for the configured Sub2 CLI."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/action-revision"
ACTORS = ["c_paper", "c_bell", "c_lantern", "c_mask", "c_umbrella", "c_ink"]
DIRECTIONS = ["down", "left", "right", "up"]
STATES = ["idle", "run", "cast", "dash", "hurt", "death"]

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    jobs = []
    for actor in ACTORS:
        for direction in DIRECTIONS:
            source = ROOT / f"game/assets/weapon-bodies/base/{actor}_{direction}.png"
            reference = OUT / f"{actor}-{direction}-reference.png"
            im = Image.open(source).convert("RGBA").resize((768, 768), Image.Resampling.NEAREST)
            im.save(reference)
            facing = {"down":"front, facing toward the viewer", "left":"left profile, facing screen LEFT", "right":"right profile, facing screen RIGHT", "up":"back view, facing AWAY; no eyes or mouth visible"}[direction]
            prompt = OUT / f"{actor}-{direction}.txt"
            prompt.write_text(f"""BINDING identity reference for the original game Incense Debt. Draw a production animation atlas of exactly the SAME paper puppet in the reference, {facing}. Preserve its specific head, face, headdress, color blocks, short body proportions and costume, including permanent offhand shield/scroll or umbrella canopy. This is NOT a character redesign. Keep fibrous ivory cut paper, vermilion, muted jade, old bronze, coarse woodblock contour, upper-left light and near top-down game view. No pixel art, 3D rendering, realistic human, background, writing, captions, labels, floor shadow, grid, checkerboard, held main-hand weapon or extra accessories. Main weapon is added separately by the game; EMPTY folded-paper grasping hand must stay visible, attached to a sleeve.

Output 1536x1536 transparent PNG, EXACTLY SIX columns by SIX rows of equally sized 256x256 cells, 36 isolated consecutive hand-drawn key poses. One complete figure in every cell. Maintain the same character scale throughout; feet have baseline at 84 percent of each cell and torso is centered. Generous clear margins. No limb crosses a cell boundary. Entire head and ribbons stay inside each cell. Do not add duplicated phantom hands or feet. Do not stretch/squash the whole source picture or use rippling image deformation: redraw actual joints, folded sleeves, alternating foot positions and facial expressions. Separate convincing poses, readable at 96x96.

ROW 1 IDLE, six frames: neutral stance, gentle natural paper tassel motion and head glance, blink middle frames (except rear view), return to neutral. No zoom or scale change.
ROW 2 WALK, six frames: actual alternating left/right foot stepping, opposing swinging sleeves and slight shoulder turn, lifted knee at frames 2 and 5, planted feet at 1 and 4; complete loop. Head size remains fixed.
ROW 3 ATTACK, six frames: wind up empty main hand near chest, elbow retracts, hand thrusts or sweeps in this facing direction at frame 3, full follow-through frame 4, recover frame 5, neutral frame 6. Visible arm/torso articulation with a clean empty hand for the weapon grip. No attack beam inside character cells.
ROW 4 DASH, six frames: weight shifts to lead leg, rear heel lifts, running lunge with bent knee, robe/ribbons trail, foot plants, controlled recovery. Fixed head and body proportions, no horizontal smearing or stretch.
ROW 5 HURT, six frames: impact flinch with eyes squeezed shut (front/profile), hand shields chest, torso leans back with elbows raised, one foot braces, hunched recovery, neutral. Clearly different defensive expression and joints, not a rotated unchanged standing sprite. No blood.
ROW 6 DEATH, six frames: knees buckle, crouch, one hand reaches floor, torso folds forward, head and shoulder settle sideways, fully fallen paper puppet lying near ground with still-visible folded head. True collapse, not merely fading standing figure, not shredded disappearing vertical strips. Do not put the final corpse back upright.

Camera and {facing} must be consistent in ALL cells. Reference only supplies appearance; create the distinct actions requested. Transparent space around every pose, no text anywhere.
""", "utf8")
            jobs.append(dict(id=f"{actor}-{direction}", actor=actor, direction=direction,
                reference=str(reference.relative_to(ROOT)), prompt=str(prompt.relative_to(ROOT)),
                output=str((OUT / f"{actor}-{direction}.png").relative_to(ROOT))))
    (OUT / "jobs.json").write_text(json.dumps(jobs, indent=2)+"\n", "utf8")
    print(f"Prepared {len(jobs)} reference-bound sheets, {len(jobs)*36} independent poses.")

if __name__ == "__main__": main()
