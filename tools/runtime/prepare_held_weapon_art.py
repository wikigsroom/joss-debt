"""Reference-locked, local edits for modular grips. Original identity pixels stay authoritative."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ACTORS = ["c_paper", "c_bell", "c_lantern", "c_mask", "c_umbrella", "c_ink"]
DIRECTIONS = ["down", "left", "right", "up"]
REGIONS = {
    "c_paper": [[[60, 42, 73, 51], [40, 51, 73, 75]], [[22, 45, 31, 53], [22, 53, 51, 74]], [[69, 43, 78, 55], [46, 55, 78, 75]], [[52, 50, 70, 69]]],
    "c_bell": [[[12, 45, 35, 87], [62, 45, 84, 87]], [[22, 43, 44, 86], [45, 52, 58, 70]], [[56, 42, 80, 88], [38, 53, 51, 69]], [[65, 48, 86, 87], [20, 58, 35, 73]]],
    "c_lantern": [[[56, 10, 75, 83], [30, 51, 57, 73]], [[55, 20, 74, 85], [28, 51, 52, 74]], [[24, 19, 40, 85], [49, 54, 70, 75]], [[55, 18, 75, 84], [30, 56, 57, 74]]],
    "c_mask": [[[9, 28, 36, 54], [9, 54, 42, 76]], [[9, 30, 37, 52], [9, 52, 42, 73]], [[66, 33, 89, 56], [61, 56, 89, 72]], [[69, 28, 89, 52], [62, 52, 89, 71]]],
    "c_umbrella": [[[29, 60, 67, 76]], [[29, 59, 58, 75]], [[38, 59, 67, 76]], [[30, 56, 69, 77]]],
    "c_ink": [[[18, 18, 36, 52], [20, 52, 43, 77]], [[27, 18, 40, 45], [27, 45, 48, 77]], [[57, 18, 79, 52], [54, 52, 79, 77]], [[62, 20, 79, 50], [54, 50, 79, 77]]],
}
PROTECTED = {
    "c_paper": [[[22, 4, 80, 44], [32, 44, 64, 50]], [[24, 3, 76, 45], [31, 45, 55, 53]], [[22, 4, 78, 46], [39, 46, 67, 53]], [[20, 5, 80, 50]]],
    "c_bell": [[[24, 10, 70, 45], [24, 36, 37, 46], [57, 36, 66, 46]], [[30, 10, 72, 50], [57, 36, 72, 54]], [[22, 10, 65, 52], [22, 38, 40, 57]], [[20, 10, 68, 48], [20, 42, 38, 58], [57, 42, 64, 52]]],
    "c_ink": [[[36, 5, 63, 55]], [[40, 5, 67, 52]], [[29, 5, 57, 53]], [[34, 12, 61, 54]]],
}
GRIPS = {
    "c_paper": [[[52, 59], [42, 59]], [[37, 61], [46, 60]], [[62, 59], [49, 60]], [[61, 57], [36, 57]]],
    "c_bell": [[[70, 54], [26, 54]], [[32, 58], [51, 59]], [[66, 54], [44, 59]], [[71, 57], [27, 59]]],
    "c_lantern": [[[61, 58], [37, 62]], [[37, 61], [60, 61]], [[62, 60], [33, 61]], [[62, 60], [36, 61]]],
    "c_mask": [[[34, 60], [66, 61]], [[34, 58], [57, 63]], [[63, 59], [45, 60]], [[66, 51], [30, 58]]],
    "c_umbrella": [[[54, 63], [40, 63]], [[38, 63], [48, 64]], [[55, 63], [43, 64]], [[60, 65], [36, 64]]],
    "c_ink": [[[37, 63], [65, 61]], [[41, 61], [53, 61]], [[63, 60], [43, 63]], [[62, 60], [36, 61]]],
}


def main():
    out = ROOT / "output/imagegen/incense-debt/held-weapons"
    out.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (1536, 1024))
    guide = canvas.copy()
    for row, direction in enumerate(DIRECTIONS):
        for column, actor in enumerate(ACTORS):
            sprite = Image.open(ROOT / f"game/assets/heroes/{actor}_{direction}.png").convert("RGBA")
            sprite = sprite.resize((256, 256), Image.Resampling.LANCZOS)
            canvas.alpha_composite(sprite, (column * 256, row * 256))
    guide = canvas.copy()
    marks = ImageDraw.Draw(guide)
    for row, direction in enumerate(DIRECTIONS):
        for column, actor in enumerate(ACTORS):
            for region in REGIONS[actor][row]:
                box = [round(v * 256 / 96) + (column * 256 if i % 2 == 0 else row * 256) for i, v in enumerate(region)]
                marks.rectangle(box, outline=(255, 0, 200, 255), width=3)
            for point in GRIPS[actor][row]:
                x, y = column * 256 + point[0] * 256 / 96, row * 256 + point[1] * 256 / 96
                marks.ellipse((x - 5, y - 5, x + 5, y + 5), fill=(0, 240, 240, 255))
    canvas.save(out / "approved-poses-edit-canvas.png")
    guide.save(out / "grip-edit-guide.png")
    (out / "grip-regions.json").write_text(json.dumps({"actors": ACTORS, "directions": DIRECTIONS, "regions": REGIONS, "grips": GRIPS}, indent=2) + "\n", "utf8")
    prompt = ROOT / "docs/incense-debt/assets/prompts/reference-locked-neutral-grips.txt"
    prompt.write_text("""Edit reference ONE in place. This is the approved in-game sprite master for the SAME original game Incense Debt, NOT a redesign. Reference TWO is a placement guide only: magenta rectangles identify editable equipment/arm patches; cyan dots identify tiny empty paper-hand grip positions. Do not copy any colored guide marks into the result. Reference THREE is the original identity master.

Output exactly the same 1536x1024 transparent 6-column x 4-row production sprite atlas, every existing head, face, costume, height, scale, facing, foot position and cell position unchanged. Rows: front/down, left, right, back/up. Columns: paper apprentice, bell weaver, lantern pilgrim, mask warden, umbrella spirit, ink clerk. Preserve the original coarse dry ink contours, worn ivory paper, vermilion fabric, dull bronze, muted jade and charcoal, with the same upper-left light. No scenery, shadows, labels, grid, glow, captions, checkerboard, text, extra bodies or extra props. Real transparent PNG.

ONLY edit the magenta equipment/arm zones: remove the paper apprentice's handheld censer and its smoke; remove the bell weaver's handheld hanging bells and tassels but preserve the head loops and their small costume bells; remove the lantern pilgrim's thin handheld staff and small staff lantern but preserve its large orange lantern HEAD exactly; remove the mask warden's rectangular hammer but preserve its face, jade cloak, armor and round OFFHAND SHIELD exactly; preserve the umbrella spirit's large vermilion canopy as a PERMANENT BODY/HEADDRESS layer (the spirit itself is a paper umbrella), and add two very small folded-paper neutral grasping hands beneath the face; remove the ink clerk's long handheld brush but preserve its tall hat, paper face and ivory OFFHAND SCROLL exactly. Fill areas formerly covered by tools with matching robe folds or transparent background, as appropriate. Do not retain a ghost tool, smoke or long grip shaft.

At the cyan guide positions place small natural neutral paper hands attached to the original sleeve/arm, with thumb and curled paper fingers loosely grasping an EMPTY space. Preserve existing offhand shield/scroll if a guide dot overlaps it. The main hand must be visible in side/back views as a tiny wrist extending from its original sleeve, without rotating the torso or turning the face toward the camera. Keep the rest of every source pose pixel position stable, especially eyes, hats, umbrella canopy, ribbons and feet. These are modular unarmed base poses to carry interchangeable weapons later, not a new animation or pose sheet.
""", "utf8")
    weapon_prompt = ROOT / "docs/incense-debt/assets/prompts/reference-locked-held-weapons.txt"
    weapon_prompt.write_text("""The supplied references are BINDING visual masters for the same original Chinese folklore game Incense Debt. Make a production atlas of TWELVE small interchangeable handheld weapon cutouts, exactly FOUR columns by THREE rows, 1536x1024 real transparent PNG. Retain each supplied weapon's distinctive shape, fibrous ivory paper, dry coarse ink outlines, vermilion bindings and matte worn bronze. Match the approved characters' near-top-down camera and upper-left light. No hands, characters, feet, scenery, shadow, labels, text, grid, icons, UI plates, checkerboard or background. Every complete weapon stays inside its cell with at least 30px transparent margin.

Each item needs a readable accessible grip/loop, not a cropped inventory emblem. Row-major order:
1. The same small squat bronze censer, plain side handle/loop exposed for a paper hand, sparse ivory folded binding, no broad smoke plume; upright.
2. ONE of the same rounded old bronze hand bells, with a short red gripping loop above and short tassel below; upright. The engine duplicates it for the two-bell grip.
3. A slender bronze hand staff with the same small elongated amber lamp at the TOP, its lower shaft visible for a waist-high grip; upright. This is the SMALL STAFF LAMP, not the character's large round lantern-head.
4. The same heavy square bronze seal hammer, short wrapped shaft at LEFT and stamp head extending RIGHT; preserve old bronze floral seal without readable writing.
5. A CLOSED compact vermilion paper umbrella weapon, the same ribs/bindings and bone shaft as the approved open umbrella, point extending RIGHT, short exposed grip at LEFT. The character's permanent wide umbrella canopy is separate; this weapon is carried folded before being thrown.
6. The same slim ivory-and-bronze ledger brush, exposed shaft grip at LEFT, fine black-and-ivory brush point extending RIGHT.
7. The same fan of five ivory offering tickets with vermilion non-letter geometric seals and square-hole coins, small bound grip at BOTTOM LEFT; paper fan opens toward RIGHT.
8. The same cluster of three vermilion firecracker tubes, worn ivory rims and a restrained small orange fuse, exposed binding grip at LEFT, open tube mouths face RIGHT.
9. The same heavy square-hole bronze coin wheel, one vermilion cloth tie, full unbroken readable ring; gripping hole in the center; mostly frontal view.
10. The same slender dark-wood soul banner staff, ivory torn wish slips and vermilion strips, a small bronze bell, accessible LOWER shaft grip; upright.
11. The same thicker judgment brush with bronze collar and red wood handle, exposed grip at LEFT and heavy black-and-ivory brush point extending RIGHT.
12. The same curved worn ivory bone knife, dark chipped spine, wrapped red hilt at LEFT and blade pointing RIGHT.

Do not invent guns or change weapon identities. Long aimed weapons are approximately horizontal, point to the right; hanging censer, bell, lamp staff and banner remain upright. Keep surface detail readable at 32-48 game pixels, use two or three major shade values, generous separated silhouettes, and true alpha edges.
""", "utf8")
    queue_path = ROOT / "docs/incense-debt/assets/runtime-production-queue.json"
    queue = json.loads(queue_path.read_text("utf8"))
    jobs = [
        {"name": "neutral-grips", "prompt": prompt.relative_to(ROOT).as_posix(), "references": [
            (out / "approved-poses-edit-canvas.png").relative_to(ROOT).as_posix()], "output": (out / "neutral-grips-single-reference.png").relative_to(ROOT).as_posix(), "background": "transparent"},
        {"name": "held-weapons", "prompt": weapon_prompt.relative_to(ROOT).as_posix(), "references": [
            "output/imagegen/incense-debt/runtime/weapons.png"],
         "output": (out / "held-weapons-reference-edit.png").relative_to(ROOT).as_posix(), "background": "transparent"},
    ]
    queue["jobs"] = [j for j in queue["jobs"] if j["name"] not in ["neutral-grips", "held-weapons"]] + jobs
    queue_path.write_text(json.dumps(queue, ensure_ascii=False, indent=2) + "\n", "utf8")
    print("Prepared two reference-bound modular equipment briefs; original art preserved.")


if __name__ == "__main__":
    main()
