"""Add ability and elite briefs against the already accepted production references."""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[2]
PROMPTS = ROOT / "docs/incense-debt/assets/prompts"
STYLE = """The attached images are binding art references for the SAME original Chinese folklore game Incense Debt. Preserve fibrous torn ivory paper, dry coarse woodblock contours, matte aged bronze, muted jade and vermilion cloth, warm small ember accents and the same upper-left light. No lettering, captions, frames, pixel art, glossy 3D, vector clipart, neon, or modern machinery. Output 1536x1024 true transparent PNG; no background or checkerboard. Each complete subject stays inside its assigned cell with generous transparent padding.\n"""

def main():
    path = ROOT / "docs/incense-debt/assets/runtime-production-queue.json"
    queue = json.loads(path.read_text("utf8"))
    jobs = [
        ("skills", STYLE + """EIGHTEEN isolated illustrated ability emblems, exactly SIX columns by THREE rows. These are tangible paper-and-bronze objects depicting the abilities, consistent with the supplied offering icons, readable when reduced to 64px. No UI plate baked into the artwork. Row-major order:
1. Ivory folded paper with three warm ash embers bursting outward.
2. Two ivory paper swallows with amber ash tails.
3. A small cross of red paper firecrackers.
4. One old bronze hand bell cutting a short vermilion cord.
5. A web of three vermilion cords tied by bronze bell knots.
6. Two bronze hand bells surrounded by two nested warm curved sound rings.
7. Red paper lantern over a small curled amber fire patch.
8. An elongated curved candle-flame dragon made of ivory paper and vermilion strips.
9. Red lantern walking on two folded paper feet above a warm fire trail.
10. Heavy square worn bronze stamp on an ivory paper seal.
11. Two bronze gate plates joined by an ivory paper shield.
12. A broken square bronze stamp splitting a square-hole coin shield.
13. Vermilion umbrella drawing three ivory ash flakes inward.
14. A small red paper umbrella with several ivory ash raindrops making a hanging veil.
15. Folded ivory wind curling behind a vermilion umbrella.
16. One thick dark calligraphy brush drawing a short red-and-black line through ivory ledger scraps.
17. Brush and three divergent dry black-and-ivory strokes.
18. An open ivory ledger with two parallel repeated dark brush marks and a red binding.
The emblems have no letters or numerals. Keep each motif visually distinct and consistent with the six approved character identities.
""", ["output/imagegen/incense-debt/characters-roster.png", "output/imagegen/incense-debt/runtime/relics-initial.png"]),
        ("elites", STYLE + """SIX isolated elite enemies, exactly THREE columns by TWO rows. Each is an identifiable stronger variation of its supplied base enemy, with damaged vermilion debt seals and worn bronze ornament, not a new species. Same near-top-down camera, feet/ground position, line weight and paper texture. No auras, arrows, diagram, or baked UI. Row-major:
1. Lantern ghost: larger cracked red lantern, jagged ivory debt scraps, dark hollow face, heavy old bronze lantern frame.
2. Paper dog: same folded ivory low hound, sharper torn red debt strips, three small bronze back plates, split paper tail.
3. Bell shooter: a hostile large bronze bell with angular ivory hands, extra red bindings and a torn seal over its hollow face.
4. Abacus spider: same horizontal abacus body and six paper legs, doubled bronze bead rows, torn red paper seals, no giant body growth.
5. Shrine paper caster: same hostile tall blank-paper face and hat, jade and charcoal robe, two folded paper seals and a broad vermilion chest binding.
6. Heavy page warrior: same tall heavy ivory paper armor, deep charcoal hollow mask, jagged layered ledger pages and a red stamped shoulder strip.
Use the three supplied regional enemy atlases to retain the corresponding species, proportions, material and visual identity.
""", ["output/imagegen/incense-debt/runtime/paper-enemies.png", "output/imagegen/incense-debt/runtime/coin-enemies.png", "output/imagegen/incense-debt/runtime/ownerless-enemies.png"])
    ]
    for name, prompt, refs in jobs:
        brief = PROMPTS / ("reference-locked-" + name + ".txt")
        brief.write_text(prompt, "utf8")
        queue["jobs"] = [j for j in queue["jobs"] if j["name"] != name]
        queue["jobs"].append({"name": name, "prompt": brief.relative_to(ROOT).as_posix(), "references": refs,
                              "output": f"output/imagegen/incense-debt/runtime/{name}.png", "background": "transparent"})
    path.write_text(json.dumps(queue, ensure_ascii=False, indent=2) + "\n", "utf8")
    print("Two reference-bound production briefs added.")

if __name__ == "__main__":
    main()
