"""Prepare identity-bound Sub2 drawings for every enemy, boss, elite and sigil.

Every page is a complete six-frame sequence in four separately drawn facings.
No pose is produced by deformation of the approved base sprite.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/creature-action-revision"
DIRECTIONS = ["down", "left", "right", "up"]
FACINGS = {
    "down": "SCREEN-DOWN FRONT VIEW: face and attacking end point toward the BOTTOM edge of the cell; the rear is toward the TOP",
    "left": "SCREEN-LEFT SIDE VIEW: the nose, face and attacking end are on the LEFT side of the cell; the tail or rear is on the RIGHT. Every pose in this row points LEFT, including hurt and recovery",
    "right": "SCREEN-RIGHT SIDE VIEW: the nose, face and attacking end are on the RIGHT side of the cell; the tail or rear is on the LEFT. Every pose in this row points RIGHT, including hurt and recovery",
    "up": "SCREEN-UP REAR VIEW: face and attacking end point away toward the TOP edge; the viewer sees only the back, rear shell or tail toward the BOTTOM. NO front-facing eyes, mouth or mask in ANY of the six cells, including the flinch and recovery",
}
ACTION_VERBS = {
    "charge": "plant the rear feet, lower the head, then lunge with articulated legs and jaws",
    "dash": "gather the limbs close, step forward into a sharp thrust, then brace and recover",
    "melee": "draw back the actual striking limb or permanent prop, swing forward, then return to a guarded stance",
    "grab": "fold the grasping appendage inward, extend the jointed appendage toward the target, close it and recover",
    "hop": "crouch the jointed legs, spring up into the attack, land with bent knees, then settle",
    "stomp": "raise one foot or lower appendage, plant it firmly with bent joints, then return to a steady stance",
    "pulse": "draw the limbs around the core, open the paper shell or raise the permanent ritual prop, then close and settle",
    "beam": "aim the permanent emitter, eye or staff, visibly brace the shoulders and unfold its aperture, then close and recover",
    "lane": "aim the permanent emitter, eye or staff, visibly brace the shoulders and unfold its aperture, then close and recover",
    "cross": "raise both existing appendages or aim the permanent emitter in a broad deliberate gesture, then recover",
    "spiral": "draw the ritual appendages inward, lift and open them in a circular casting gesture, then lower them",
    "petals": "fold the existing petals or ritual appendages inward, open them in a deliberate blossom gesture, then recover",
    "rain": "lift the permanent ritual prop or open the existing wings upward, cast with a clear upward gesture, then lower them",
    "lantern_rain": "lift the permanent lantern-bearing arms or lantern assembly, open the paper lamps, then settle",
    "summon": "gather the paper limbs near the chest, extend both existing appendages in a commanding ritual gesture, then lower them",
    "judgment": "draw back the permanent seal, head or ritual tool, make a firm downward pronouncement gesture, then brace and recover",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def roster(catalog):
    actors = []
    for kind, collection, folder in [("enemy", "enemies", "enemies"), ("boss", "bosses", "bosses"), ("elite", "elite_variants", "elites")]:
        for row in catalog[collection]:
            spec = row
            if kind == "elite":
                base = next(item for item in catalog["enemies"] if item["id"] == row["base_enemy"])
                spec = dict(base, **row)
            source = ROOT / f"game/assets/{folder}/{row['id']}.png"
            if not source.is_file():
                raise FileNotFoundError(source)
            actors.append(dict(id=row["id"], name=row["name"], kind=kind, spec=spec,
                               source=source.relative_to(ROOT).as_posix(), source_sha256=digest(source),
                               states=["attack_a", "attack_b", "attack_c", "hurt"] if kind == "boss" else ["attack", "hurt"],
                               frame_size=256 if kind == "boss" else 128))
    # Boss loan-note minions are live, damageable, attacking entities with their
    # own sprite identity. They must not be hidden behind the catalog's e01 row.
    source = ROOT / "game/assets/relics/r06.png"
    actors.append(dict(id="sigil", name="借据纸签", kind="summon", source=source.relative_to(ROOT).as_posix(),
                       source_sha256=digest(source), states=["attack", "hurt"], frame_size=128,
                       spec=dict(art_brief="the approved hanging loan-note paper talisman and its permanent binding; a damageable paper seal minion", pattern="dart")))
    return actors


def attack_description(actor, state):
    spec = actor["spec"]
    if actor["id"] == "e02":
        return "crouch the four jointed paper legs, plant the rear paws, open the folded jaws in a biting lunge, plant the front paws, then recover; do not turn the quadruped into a humanoid"
    family = str(spec.get("attack_family", spec.get("pattern", "")))
    if state == "attack_b":
        family = str(spec.get("secondary_family", family))
    action = ACTION_VERBS.get(family, "gather the existing limbs, tip the head or permanent emitter toward the target, open its real mouth or emitting aperture with a clear casting gesture, then retract and recover")
    if state == "attack_c":
        action = "use the most emphatic combined ritual gesture: " + action + "; begin low, lift the actual appendages or permanent prop higher at impact, then visibly brace and recover"
    phases = spec.get("phases", [])
    if actor["kind"] == "boss" and not spec.get("attack_family") and phases:
        index = {"attack_a": 0, "attack_b": 1, "attack_c": 2}[state]
        action += "; this boss attack has the original phase concept: " + phases[index]
    return action


def prompt_text(actor, states):
    spec = actor["spec"]
    brief = spec.get("art_brief", "preserve every distinctive element of the attached original game sprite")
    rows = []
    row_order = []
    for direction in DIRECTIONS:
        for state in states:
            row_order.append(dict(state=state, direction=direction))
            n = len(row_order)
            if state == "hurt":
                sequence = ("six independently drawn impact and recovery poses: 1 notice the impact and flinch; 2 squeeze the eyes / recoil the real joints; "
                            "3 shield the core with existing appendages and brace a foot or base; 4 compress the posture by bending real limbs, not scaling the image; "
                            "5 begin recovery; 6 return to a stable neutral stance. No blood, no extra detached limbs, no whole-picture rotation, deformation or fading.")
            else:
                sequence = (f"{attack_description(actor, state)}. Six independently drawn poses: "
                            "1 neutral ready stance; 2 visibly prepare / retract; 3 extend the attacking limb, jaws, emitter or ritual prop at the actual strike; "
                            "4 complete the follow-through; 5 recover; 6 stable neutral stance. Anatomical articulation, visible intentional movement, fixed body proportions.")
            rows.append(f"ROW {n}: {state.upper()}, {FACINGS[direction]}. {sequence}")
    text = f"""Create a production animation atlas for the ORIGINAL Incense Debt paper creature {actor['name']} ({actor['id']}). The attached single creature is a BINDING identity reference, not inspiration for a redesign. Identity description: {brief}.

Keep EXACTLY this creature's own silhouette family, face / eyes, body parts, costume, permanent objects and color blocks. Keep the original number of legs, heads, horns, wings, lanterns or body sections. For a nonhumanoid do not invent human arms or legs. A permanent abacus, lantern, shell, mask, seal, instrument or hanging paper binding stays attached and recognizable. Preserve fibrous matte cut paper, woodblock ink outlines, the specific palette from this reference, the same near top-down game camera and upper-left lighting. No 3D, photorealism, pixel art, watercolor haze, universal new red ribbons, unrelated weapons, extra accessories or changed species.

CRITICAL SCREEN COORDINATES, never the creature's anatomical left/right: rows 1 and 2 face the BOTTOM of the image; rows 3 and 4 have the HEAD ON THE LEFT and REAR ON THE RIGHT; rows 5 and 6 have the HEAD ON THE RIGHT and REAR ON THE LEFT; rows 7 and 8 show the BACK ONLY, with the head pointing away toward the TOP. In particular, row 8 MUST remain a rear view in ALL six flinch/recovery drawings. A hurt reaction bends joints without turning around. Never exchange these rows and never insert a front view in a rear-view row.

Output a portrait transparent PNG of 1536x2048: EXACTLY SIX columns by EIGHT rows, equal 256x256 cells. All FORTY-EIGHT cells must contain exactly one complete creature pose. Each row is one SIX-frame sequence, read left to right. Leave at least 24 pixels of EMPTY transparent gutter on each side inside every cell. Center the creature and keep its standing / resting base at 84 percent of each cell. Same body and head scale in all cells, including side and rear views. Every head, limb and permanent prop remains inside its own cell. No scenery, platform, floor, shadow, labels, numerals, grid lines, borders, checkerboard or any lettering anywhere. Do not draw projectile beams, explosions, motion streaks or floating attack effects inside the body atlas; effects are rendered separately by the engine.

This task requires ACTUAL DISTINCT DRAWINGS, not copying the unchanged reference, rotating it, distorting / warping its pixels, recoloring it or changing the global image scale. Redraw real limb bends, wing joints, mouth opening, shell / paper fold articulation, weight shifts and defensive expressions. Keep four direction views genuinely drawn; the back view shows the back of the creature rather than front eyes. Do not fill cells with mirrored or identical copies. The creature may move its own permanent objects but its identity and anatomy must stay stable. Clear silhouettes readable at {actor['frame_size']}x{actor['frame_size']} game scale.

""" + "\n\n".join(rows) + "\n\nExactly six columns, eight rows. Transparent background. No text. Preserve this specific original creature in all 48 independent poses.\n"
    return text, row_order


def direction_prompt(actor, direction):
    states = actor["states"]
    full_text, _ = prompt_text(actor, states[:2])
    identity_constraints = full_text.split("\nCRITICAL SCREEN COORDINATES", 1)[0]
    rows = []
    for index, state in enumerate(states, 1):
        action = "flinch, recoil real joints, shield the core, brace, recover and return to neutral" if state == "hurt" else attack_description(actor, state)
        rows.append(f"ROW {index}, {state}: {action}. Draw SIX genuinely different articulated poses, left to right. Keep the same {direction.upper()} facing in every frame, even at maximum impact. Never turn toward the viewer during a hurt reaction.")
    return identity_constraints + f"""

This is a SINGLE FACING correction, not a turn-around sheet. EVERY cell must use {FACINGS[direction]}. The attached orientation guide already points toward this screen direction. Use it to understand orientation, then independently REDRAW the creature's joints and animation poses. The game will use the generated drawings, never a mirrored or warped copy of a finished animation. Do not copy the same pose six times.

Output transparent PNG {1536}x{len(states)*256}, EXACTLY SIX columns by {len(states)} rows of equal square cells. A row is a six-frame sequence in the SAME camera view. All {len(states)*6} cells show this ONE creature facing the SAME direction. Empty transparent gutters at least 24px on every side inside each 256px cell; standing base at 84 percent. Keep original anatomy, palette, permanent props and paper texture, stable body/head scale throughout. No text, lettering, background, shadows, arrows, grid, FX, blood, additional limbs or accessories.

For attacks: columns 1 ready, 2 prepare, 3 actual strike, 4 follow-through, 5 recovery, 6 neutral. For hurt: columns 1 flinch, 2 recoil, 3 brace, 4 crouch with real joint bends, 5 recover, 6 neutral.

""" + "\n\n".join(rows) + f"\n\nALL {len(states)*6} POSES FACE {direction.upper()}. Transparent background. Six columns, {len(states)} rows.\n"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for folder in ["references", "prompts", "raw", "logs"]:
        (OUT / folder).mkdir(exist_ok=True)
    catalog = json.loads((ROOT / "game/data/catalog.json").read_text("utf8"))
    actors = roster(catalog)
    correction_path = OUT / "direction-corrections.json"
    corrections = json.loads(correction_path.read_text("utf8")) if correction_path.is_file() else {}
    jobs = []
    for actor in actors:
        reference = OUT / "references" / (actor["id"] + ".png")
        with Image.open(ROOT / actor["source"]) as seed:
            seed = seed.convert("RGBA")
            reference_canvas = Image.new("RGBA", (1024, 1024))
            seed = seed.resize((768, 768), Image.Resampling.NEAREST)
            reference_canvas.alpha_composite(seed, (128, 128))
            reference_canvas.save(reference)
        pages = [["attack_a", "hurt"], ["attack_b", "attack_c"]] if actor["kind"] == "boss" else [["attack", "hurt"]]
        for index, states in enumerate(pages):
            identity = actor["id"] + ("-primary" if index == 0 else "-secondary")
            text, rows = prompt_text(actor, states)
            actual_directions = corrections.get(actor["id"], {}).get("actual_row_directions", {}).get(identity, {})
            if actual_directions:
                for row, item in enumerate(rows):
                    direction = actual_directions.get(str(row))
                    if direction:
                        if direction not in DIRECTIONS: raise ValueError("Unknown inspected row direction")
                        item["direction"] = direction
            omitted = corrections.get(actor["id"], {}).get("omit_rows", {}).get(identity, [])
            if omitted:
                rows = [dict(item, source_row=row) for row, item in enumerate(rows) if row not in omitted]
            prompt = OUT / "prompts" / (identity + ".txt")
            prompt.write_text(text, "utf8")
            target = OUT / "raw" / (identity + ".png")
            jobs.append(dict(id=identity, actor=actor["id"], kind=actor["kind"], states=states,
                             reference=reference.relative_to(ROOT).as_posix(), reference_sha256=digest(reference),
                             prompt=prompt.relative_to(ROOT).as_posix(), prompt_sha256=digest(prompt),
                             output=target.relative_to(ROOT).as_posix(), source=actor["source"], source_sha256=actor["source_sha256"],
                             size="1536x2048", columns=6, rows=8, row_order=rows, model="gpt-image-2.5", quality="high"))
        for direction in corrections.get(actor["id"], {}).get("redraw_directions", []):
            if direction not in DIRECTIONS: raise ValueError("Unknown correction facing")
            identity = actor["id"] + "-" + direction + "-correction"
            guide = OUT / "references" / (identity + ".png")
            pose_reference = corrections.get(actor["id"], {}).get("references", {}).get(direction)
            with Image.open(ROOT / (pose_reference or actor["source"])) as seed:
                seed = seed.convert("RGBA")
                if direction == "left" and not pose_reference: seed = ImageOps.mirror(seed)
                canvas = Image.new("RGBA", (1024, 1024))
                canvas.alpha_composite(seed.resize((768, 768), Image.Resampling.NEAREST), (128, 128))
                canvas.save(guide)
            prompt = OUT / "prompts" / (identity + ".txt")
            text = direction_prompt(actor, direction)
            review_constraints = corrections.get(actor["id"], {}).get("direction_notes", {}).get(direction)
            if review_constraints:
                text += "\nMANDATORY CORRECTION FROM SOURCE REVIEW: " + review_constraints + "\n"
            prompt.write_text(text, "utf8")
            jobs.append(dict(id=identity, actor=actor["id"], kind=actor["kind"], states=actor["states"],
                             reference=guide.relative_to(ROOT).as_posix(), reference_sha256=digest(guide),
                             reference_derivation="Orientation guide only; the final poses must be independently generated, never mirrored from another output pose.",
                             prompt=prompt.relative_to(ROOT).as_posix(), prompt_sha256=digest(prompt),
                             output=(OUT / "raw" / (identity + ".png")).relative_to(ROOT).as_posix(),
                             source=actor["source"], source_sha256=actor["source_sha256"],
                             size=f"1536x{len(actor['states'])*256}", columns=6, rows=len(actor["states"]),
                             row_order=[dict(state=s, direction=direction) for s in actor["states"]], model="gpt-image-2.5", quality="high"))
        for direction in corrections.get(actor["id"], {}).get("seed_directions", []):
            identity = actor["id"] + "-" + direction + "-seed"
            prompt = OUT / "prompts" / (identity + ".txt")
            if actor["id"] == "b06":
                text = (f"Draw ONE production game sprite of the exact attached {actor['name']} ({actor['id']}) in a new SCREEN-{direction.upper()} side view. This is a camera-facing reference pose, NOT an animation sheet. Preserve its original cut-paper material, ink outlines, palette, body proportions, original roof, lantern arms, ribbons, feet and six-coin front panel. No human face or new body parts. Same near top-down game camera, lighting from upper left.\n\n"
                    f"The creature is turned to SCREEN {direction.upper()}: its FRONT wall and six-coin emitting panel must be on the {direction.upper()} end of the silhouette. Its wide rear/side wall extends toward the opposite side. Show the front panel obliquely, compressed by perspective, never as the same frontal 3-by-2 coin grid facing the viewer. This is a real independently drawn side view of the same object, not tilting or spinning the existing flat image. The opposite wall and flank of the shrine are visible behind the front panel. The lantern-bearing arms and planted legs belong to this same side-facing body. The front emitter aims horizontally toward the {direction.upper()} edge, not toward the viewer.\n\n"
                    "Draw only one complete creature, standing neutrally, centered on transparent 1024x1024 PNG with 15 percent empty margin. Keep the original readable identity and permanent structures. NO atlas, multiple poses, text, labels, arrows, scenery, ground, shadow, poster design, floating FX or new accessories.")
            else:
                text = (f"Draw ONE neutral production sprite of the EXACT attached original {actor['name']} ({actor['id']}) in this camera view: {FACINGS[direction]}. This is an orientation reference, not an animation sheet or redesign.\n\n"
                    f"Preserve this original creature's species, silhouette family, paper construction, number of body segments, original limbs, bindings and permanent objects. Identity: {actor['spec'].get('art_brief', 'Every distinctive feature of the attached original sprite is binding')}. Keep the exact matte fibrous paper, woodblock outlines, original palette, body scale, near top-down game camera and upper-left light.\n\n"
                    "For a rear view the front mouth, eyes and face are completely hidden: show the same creature's tail or closed rear body, not a second mouth, mirrored frontal face or new mask. For a side view its head/attacking end points to the requested SCREEN side. Redraw real depth and occlusion, not spinning or warping the flat source picture.\n\n"
                    "Only ONE complete neutral creature centered on transparent 1024x1024 PNG, 15 percent empty margin, standing base at 84 percent. No extra body parts, new accessories, floating effects, ground, shadow, multiple sprites, text, letters, labels, arrows or background.")
            review_constraints = corrections.get(actor["id"], {}).get("seed_notes", {}).get(direction)
            if review_constraints:
                text += "\nMANDATORY CORRECTION FROM SOURCE REVIEW: " + review_constraints + "\n"
            prompt.write_text(text + "\n", "utf8")
            jobs.append(dict(id=identity, actor=actor["id"], kind=actor["kind"], purpose="reference_pose", states=[],
                             reference=reference.relative_to(ROOT).as_posix(), reference_sha256=digest(reference),
                             prompt=prompt.relative_to(ROOT).as_posix(), prompt_sha256=digest(prompt),
                             output=(OUT / "raw" / (identity + ".png")).relative_to(ROOT).as_posix(),
                             source=actor["source"], source_sha256=actor["source_sha256"], size="1024x1024", columns=1, rows=1,
                             row_order=[], model="gpt-image-2.5", quality="high"))
    plan = dict(version=2, method="independently_drawn_six_frame_poses", directions=DIRECTIONS,
                actors=actors, jobs=jobs, expected_actors=len(actors), expected_jobs=len(jobs),
                expected_action_poses=sum(len(actor["states"])*4*6 for actor in actors))
    (OUT / "plan.json").write_text(json.dumps(plan, ensure_ascii=False, indent=2)+"\n", "utf8")
    print(f"Prepared {len(actors)} complete creature identities, {len(jobs)} pages, {plan['expected_action_poses']} independently drawn attack/hurt poses.")


if __name__ == "__main__":
    main()
