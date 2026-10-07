"""Author reference-bound production briefs for the remaining content. No credentials."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
PROMPTS = ROOT / "docs/incense-debt/assets/prompts"
OUT = "output/imagegen/incense-debt/runtime/"
STYLE = """The supplied images are binding art references for the SAME original game Incense Debt. Match their coarse woodblock ink contour, torn fibrous ivory paper, vermilion ribbons, matte aged bronze, muted jade and upper-left light. Do not redesign the art style. No glossy 3D, no pixel art, no clean vector clipart, no science fiction, no lettering or labels. Tangible folklore paper-and-wood objects with readable silhouettes at gameplay scale.
"""
ATLAS = """Output one 1536x1024 PNG with true transparent alpha. Each assigned grid cell contains exactly one complete isolated subject, centered with generous transparent padding and no crossing into another cell. No scene, no frame, no checkerboard, no caption. Consistent near-top-down game orientation with readable fronts and short shadows. Keep proportions coherent across the sheet.
"""


def main():
    jobs = []
    def job(name, brief, references, background="transparent"):
        path = PROMPTS / ("reference-locked-" + name + ".txt")
        path.write_text(STYLE + brief, "utf-8")
        jobs.append({"name": name, "prompt": path.relative_to(ROOT).as_posix(), "references": references,
                     "output": OUT + name + ".png", "background": background})
    paper = OUT + "paper-temple-arena.png"
    roster = "output/imagegen/incense-debt/characters-roster.png"
    enemy_ref = OUT + "paper-enemies.png"
    relic_ref = OUT + "relics-initial.png"
    job("ownerless-temple-arena", """Create the clean production room background and binding environment design for region three, the Ownerless Temple. Use exactly the supplied arena's rectangular walkable footprint, fixed near-top-down camera, upper alcoves, side walls, corner guardian footprints and lower central exit. Output opaque full-bleed 1536x1024, no actors, no UI, no projectiles, no inset.
The same temple is now an abandoned ledger sanctuary: very large charcoal-black shrine alcoves containing BLANK ivory name tablets, sparse torn vermilion cloth, pale old ivory and jade-gray stone floor, subtle red seal fragments and torn paper edge decorations. Perimeter guardians are the same wood-and-paper beasts, wrapped with blank ledger scraps. Lower the contrast of the central floor; keep x=80..1456, y=165..850 free of large objects. A faint circular stamp pattern and branching paper seams echo the supplied first-room floor motif. Architecture, hand-painted surface, perspective and light match the reference; only the region's materials and motifs change. No bright white bloom, no central statue, no baked pillars in the combat area, no readable words or imaginary text.
""", [paper, roster], "opaque")
    job("coin-enemies", ATLAS + """Exactly FOUR columns by TWO rows, eight hostile enemy base poses, one per cell. Same enemy proportions and perspective as the supplied first-region enemy atlas; distinct threatening dark or hollow faces. Row-major order:
1. Coin shield guard: stout folded paper soldier, a square old bronze shield with a clear square-hole cash emblem, short dagger and vermilion cord, angled shield visible at its front.
2. Abacus spider: squat horizontal wooden abacus body, worn bronze beads, six folded charcoal paper legs, dark hollow face on the front frame. Silhouette unmistakably a crawling abacus.
3. Gold paper moth: sharp folded matte gold wings, charcoal abdomen, torn ivory edges, two narrow red antennae, aggressive small hollow face.
4. Wish scale ghost: lanky worn ivory paper ghost carrying an old bronze balance and heavy round square-hole cash weights, a red cord belt, hunched and menacing.
5. Coin collecting paper hound: same folded white paper dog species as the supplied first atlas, but a heavy bronze coin collar, sharper black face, torn vermilion stripes and low lunging body.
6. Coin breaker: stocky ragged paper artisan with a dark split mask, a bronze hammer and a broken square-hole cash disk, short red apron.
7. Floating cash bell: large matte bronze bell with dangling ivory and red paper streamers, dark slit face, no humanoid legs, compact floating silhouette.
8. Debt accountant: hostile tall black paper hat, narrow hollow paper face, heavy ragged ledger, small bronze abacus and vermilion bindings, visibly meaner and more damaged than the friendly playable ink clerk.
""", [enemy_ref, roster])
    job("ownerless-enemies", ATLAS + """Exactly FOUR columns by TWO rows, eight hostile enemy base poses, one per cell. Same proportions and perspective as the supplied first-region enemies. Row-major order:
1. Nameless paper guard: broad charcoal-and-ivory paper armor, blank broken mask, tall torn paper blade and a small red stamp knot.
2. Ink page worm: crawling curled ledger pages making a segmented low worm, dark ink maw, ivory torn corners and sparse red stitching.
3. Empty face lamp: round pale ivory paper lantern with a blank hollow black face cavity, charcoal cap, vermilion tassels, no friendly oval eyes.
4. Seal pillar: tall carved charcoal wooden stamp column with layered ivory ward strips, one glowing muted jade seal-shaped core, jagged folded paper arms, no readable characters.
5. Broken string puppet: crooked hanging paper limbs, dark hollow mask, broken red suspension cords and torn ivory cape, distinct asymmetrical silhouette.
6. Interest official: thin dark paper magistrate with a steep tall black hat, hollow face, two small bronze warning bells and ripped red ledger ribbons.
7. Rolled ledger beast: heavy four-legged beast made of tightly rolled ivory ledger books and charcoal page armor, a wide dark ink mouth, bronze bindings and a short red tail.
8. Ash wish shadow: a small ominous soot-black paper apparition with a burnt ivory face shard, red string core and a pointed ink brush arm; irregular torn outline, no translucent background smoke.
""", [enemy_ref, roster])
    mid = ["r04", "r05", "r06", "r07", "r08", "r12", "r13", "r14", "r15", "r16", "r20", "r21", "r22", "r23", "r24", "r28", "r29", "r30"]
    end = ["r31", "r32", "r36", "r37", "r38", "r39", "r40", "r44", "r45", "r46", "r47", "r48", "r49", "r50", "r51", "r52", "r53", "r54"]
    shapes = {"r04": "ivory wax tear resting on a small old bronze saucer", "r05": "two tied vermilion paper firecrackers with a tiny amber fuse",
              "r06": "torn ivory ward with charred edges and one red geometric seal", "r07": "small closed bronze lamp with an amber flame inside its torn paper window",
              "r08": "three tiny ivory paper flames joined by a red knot", "r12": "short dark bronze hook tied to a red wish cord",
              "r13": "two square-hole bronze coins joined by one red cord", "r14": "a distinctive figure-eight red rope clasp with small bronze tips",
              "r15": "small ivory stitched booklet tied by a red string", "r16": "compact red cord spiderweb on a small ivory paper frame",
              "r20": "a short burnt incense stick with a tiny ember", "r21": "shallow old bronze soul dish holding ivory ash",
              "r22": "wide low bronze ash collection tray with a red cord rim", "r23": "small dark bronze ash wheel with ivory fragments in the central hole",
              "r24": "miniature squat bronze furnace with several folded ivory wish slips", "r28": "one broken bronze cash coin with a vermilion ward ribbon",
              "r29": "ivory protective paper knot with a red seal and a warm small core", "r30": "small round tarnished bronze mirror with a red hanging loop",
              "r31": "thick old bronze door nail with an ivory ward wrap", "r32": "tiny seated ivory paper figure wrapped in bronze armor",
              "r36": "one ivory feather with an ash-black tip and red binding", "r37": "two small bronze bells linked by a curved ivory paper strip",
              "r38": "small triangular ivory-and-red wish pennant", "r39": "a curled torn ivory paper trail with a red cord tip",
              "r40": "a three-blade folded ivory paper pinwheel with a bronze hub", "r44": "long narrow ivory name slip pierced by an ink-black brush stroke",
              "r45": "small square bronze cancellation stamp with a dark handle", "r46": "a folded charcoal contract sheet sealed by a vermilion knot",
              "r47": "two rolled ivory ledger scrolls crossed and bound in red", "r48": "thick closed ivory ledger with charcoal cover and three bronze clasps",
              "r49": "ivory cloth patch embroidered with a red debt cord and ash threads", "r50": "pair of tiny vermilion paper shoes with amber lamp tassels",
              "r51": "small dark bronze inkstone containing pale ash and a short ivory brush", "r52": "square vermilion seal stamp with a black ink tip and red cord",
              "r53": "a small ivory paper lantern protected by a thick red rope loop", "r54": "a short tied bundle of incense with a bronze cash charm"}
    for name, ids in [("relics-mid", mid), ("relics-end", end)]:
        details = "Exactly SIX columns by THREE rows; eighteen compact relic icons, one per cell. Match the supplied initial icon atlas closely. Row-major order:\n"
        details += "\n".join(f"{i+1}. {shapes[id]}." for i, id in enumerate(ids))
        job(name, ATLAS + details + "\nUse humble tactile objects, not generic symbols. No letters or numbers in the image.", [relic_ref, roster])
    job("optional-bosses", ATLAS + """Exactly TWO columns by ONE row. Two large distinct fully visible boss bodies, matching the scale, brushwork and menace of the supplied boss atlas. Clear transparent separation. No scene, no additional characters.
Left: the Nameless Creditor, a tall dark charcoal-and-vermilion paper magistrate whose ivory mask is split into two displaced blank halves, a ragged cloak of blank name slips, bronze cash chains, two dangling small blank face medallions, heavy old ledger and one carved bronze name seal. An unreadable face, no lettering, angular theatrical silhouette.
Right: the Interest Page Colossus, a huge broad towering beast made from layered and rolled ivory ledger pages, dark wooden ribs, three triangular vermilion paper seals around a hollow bronze heart cavity, short heavy paper legs and long folded-page arms. Large torn page crown and matte bronze bells, ominous and distinct from the main shrine god in the supplied atlas.
""", [OUT + "bosses.png", roster])
    job("hub-arena", """Create the clean binding design and production background for the game's peaceful Return Wish Courtyard. Same rectangular near-top-down camera, ink contour, paper/wood architecture and dim warm night lighting as the supplied temple arena. Opaque full-bleed 1536x1024. No character, no UI, no text, no inset, no projectile.
An enclosed folk shrine courtyard with a large open jade-gray stone floor. Upper center is a small warm-lit shrine gate, red torn fabric awnings at the upper left and right, an old sewing table with ivory paper scraps on the left, a wooden abacus stand upper right, a small lantern merchant stall on the right, and a low blank-name-tablet stand lower left. Place furniture close to the perimeter, leaving the center walkable. Bottom center is a stone step entering the temple; dim warm lanterns light the lower posts. Friendly and quiet, the same humble tangible materials as the game's battle rooms. No text signs, no central statue, no photorealism, no modern furniture.
""", [paper, roster], "opaque")
    job("npcs", ATLAS + """Exactly THREE columns by TWO rows. Five friendly hub NPCs and one small training prop, matching the supplied roster's approachable faces and costume texture. Row-major order:
1. The Wish Weaver: a short elderly ivory paper woman, kind black oval eyes, patched red-and-ivory apron, gray paper hair bun, holding a bronze sewing tray and thick red thread.
2. The Copper Abacus: a small upright old wood-and-bronze abacus with two ivory paper hands, short charcoal feet, a friendly simple face on the top crossbar, red ribbon knot.
3. The Faceless Accountant: squat ivory paper clerk with a square dark hat, entirely blank ivory face, wide charcoal ledger, bronze coin cord and modest red coat.
4. The Lantern Peddler: small friendly paper raccoon with a red apron, black eye markings, a little wooden lantern rack on its back, bronze cash string, warm ivory face.
5. The Name Tablet: a small upright old wooden blank-name tablet on two tiny folded ivory feet, one vermilion seal corner, friendly shape, no writing or face.
6. A small training stand with one folded ivory paper target and a bronze round base, red ribbon, no numbers or letters.
""", [roster, paper])
    manifest = ROOT / "docs/incense-debt/assets/runtime-production-queue.json"
    manifest.write_text(json.dumps({"provider": "sub2-image-gen", "model": "gpt-image-2.5", "quality": "high", "jobs": jobs}, ensure_ascii=False, indent=2) + "\n", "utf-8")
    print(f"Prepared {len(jobs)} reference-bound production briefs.")


if __name__ == "__main__":
    main()
