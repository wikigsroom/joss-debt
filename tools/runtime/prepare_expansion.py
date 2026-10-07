"""Author the eleven-floor campaign and reference-bound Sub2 production queue."""
from pathlib import Path
import json
from environment_themes import THEMES, ROOM_STYLE, reviewed_room_rects

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/incense-debt/expansion"
PROMPTS = ROOT / "docs/incense-debt/assets/prompts/expansion"
STYLE = "The references are binding art for Incense Debt: coarse woodblock ink contour, fibrous torn ivory paper, vermilion ribbons, matte aged bronze and muted jade; upper-left lighting, tactile Chinese folklore paper puppets. Preserve this exact visual family. No lettering, no glossy 3D, no vector clipart, no pixel art, no UI. "
BOSSES = [
 ("灯海巡夜", "a massive walking bronze lantern boat with six ivory lantern eyes", "orbit", "spiral", "lantern_rain"),
 ("铜锣镇魂", "a broad masked gong bearer with two monumental bronze cymbal arms", "stomp", "pulse", "cross"),
 ("纸嫁娘", "a tall vermilion wedding-paper bride with torn veil and a folding fan", "blink", "fan", "petals"),
 ("瓮中龙", "a coiled paper river dragon escaping a cracked bronze urn", "serpent", "snake", "flood"),
 ("断桥渡客", "a hunched boatman carrying a long broken ivory oar and river reeds", "strafe", "lane", "wake"),
 ("香山伏虎", "a squat ivory tiger shrine with curled bronze claws and smoking incense back", "pounce", "charge", "ember"),
 ("钱雨财神", "a plump black-paper money god wearing stacked bronze coin armor", "orbit", "coins", "grid"),
 ("绣骨织母", "a skeletal red-thread weaver with eight wooden loom arms", "anchor", "web", "cross"),
 ("抬棺四相", "four small blank masked bearers fused around an ivory funeral palanquin", "procession", "lane", "summon"),
 ("镜面无常", "a thin symmetrical black and ivory mirror guardian with twin mirrored masks", "blink", "reflect", "fan"),
 ("墨池蛟", "a serpentine black ink-paper fish with bronze brush whiskers", "serpent", "snake", "ink"),
 ("酒葫芦仙", "a round aged ivory gourd with wooden feet and a red rope waist", "bounce", "lob", "pulse"),
 ("烛骨夫人", "a tall melted-ivory candle matron with many short orange flames", "strafe", "candle", "ember"),
 ("钟楼巨童", "a massive bronze bell child with swinging wooden hammer hands", "stomp", "pulse", "lob"),
 ("伞下千面", "a wide red umbrella monster with many dangling blank paper faces", "orbit", "petals", "summon"),
 ("剪纸螳螂", "a long ivory folded-paper mantis with two red scissor forearms", "pounce", "charge", "cross"),
 ("灰窑山魈", "a hunched charcoal kiln ape with torn furnace-mouth chest", "stomp", "ember", "lob"),
 ("鹿角守山", "a proud ivory paper deer with branching bronze antlers and red tassels", "strafe", "fan", "roots"),
 ("雷纹鼓王", "a giant red-and-black ceremonial drum with bronze thunder rods", "anchor", "cross", "pulse"),
 ("莲座偃师", "a blank-faced wooden puppet seated on a huge jade-paper lotus", "orbit", "petals", "web"),
 ("石狮吞契", "a low heavy charcoal stone lion with folded ivory scroll mane", "pounce", "charge", "coins"),
 ("水车鬼匠", "a spinning wooden waterwheel man with bronze bucket arms", "bounce", "spiral", "flood"),
 ("枯树祖灵", "a branching wooden tree elder with torn ivory prayer leaves", "anchor", "roots", "summon"),
 ("赤线双生", "a pair of joined ivory marionettes tied by thick vermilion threads", "procession", "web", "reflect"),
 ("戏台傀首", "a large opera puppet head inside a vermilion stage arch, two rod hands", "blink", "fan", "summon"),
 ("铁笔判首", "a narrow bronze quill magistrate with a heavy inkstone robe", "strafe", "lane", "ink"),
 ("三头狱犬", "a three-headed charcoal paper hound with short bronze chains", "pounce", "charge", "triple"),
 ("灯骨巨蟹", "a wide bronze and ivory crab carrying a row of small shrine lanterns", "strafe", "grid", "candle"),
 ("白绫蛇后", "a long coiled funeral-silk paper serpent with red knot crown", "serpent", "snake", "web"),
 ("踏云门神", "a towering ivory gate guardian with two wide jade-paper shields", "stomp", "cross", "reflect"),
 ("守名大判", "a solemn colossal blank-faced paper magistrate with a bronze name-scale and a broken red seal", "procession", "judgment", "summon"),
 ("万愿总账", "a vast many-armed ivory ledger deity with an open bronze heart, red thread constellation and torn blank pages", "orbit", "ledger", "spiral"),
]
ENEMIES = [
 ("火签雀", "small folded ember sparrow with a red incense tail", "dart", "chase", 10, 82),
 ("钱壳蜗", "round bronze coin snail with paper feelers", "lob", "anchor", 23, 44),
 ("绳足童", "tiny red-thread child with long wooden stilt legs", "hop", "hop", 12, 112),
 ("瓮口蛙", "wide ivory urn frog with a bronze open mouth", "triple", "retreat", 22, 58),
 ("墨滴鱼", "small long black ink fish floating over a jade paper fin", "snake", "sine", 12, 106),
 ("竹叶刃", "thin ivory bamboo blade spirit with red sash", "dash", "strafe", 14, 125),
 ("烛背龟", "broad bronze tortoise carrying a melted ivory candle", "ember", "anchor", 27, 34),
 ("灰面蛾", "tiny charcoal moth with torn ivory wings and ash eyes", "orbit", "orbit", 10, 124),
 ("纸铲兵", "stocky paper soldier holding a short wooden spade", "melee", "chase", 20, 78),
 ("雨蓑客", "tall reed-cloak walker with a small bronze rain bell", "rain", "strafe", 16, 72),
 ("响铃蝠", "small bronze bell bat with ragged paper wings", "ring", "orbit", 13, 105),
 ("灯芯蚁", "tiny black paper ant carrying an orange wick", "mine", "chase", 9, 145),
 ("钱袋獾", "fat torn ivory coin-bag badger with bronze claws", "bounce", "retreat", 25, 56),
 ("莲瓣灵", "medium jade paper lotus dancer with pointed ivory petals", "petals", "orbit", 17, 88),
 ("断页狐", "narrow ivory paper fox with several red bookmark tails", "blink", "blink", 15, 106),
 ("铜钉侍", "short broad bronze nail guard with square paper mask", "beam", "anchor", 21, 48),
 ("井绳鬼", "tall red rope ghost with a wooden well bucket head", "pull", "sine", 18, 73),
 ("扇骨妖", "wide ivory folding fan creature with many wooden feet", "fan", "strafe", 19, 60),
 ("灰窑犬", "low charcoal paper dog with a small furnace chest", "dash", "chase", 15, 118),
 ("青苔石童", "heavy square jade-stained stone child with paper limbs", "stomp", "anchor", 29, 31),
 ("锁契虫", "long segmented red-and-bronze chain centipede", "snake", "sine", 17, 85),
 ("纸笛客", "thin ivory flute player in a red ragged conical hat", "spiral", "strafe", 16, 82),
 ("镜鳞蛇", "small black paper snake with bronze mirror scales", "reflect", "orbit", 14, 108),
 ("灯蕊蜂", "tiny vermilion paper bee with a glowing bronze stinger", "dart", "hop", 9, 151),
 ("灰线蛛", "wide wooden-legged ash spider with an ivory scroll abdomen", "web", "retreat", 22, 76),
 ("墨冠鹤", "tall elegant black paper crane with red ink crown", "beam", "strafe", 18, 102),
 ("莲座瓢虫", "round jade-paper beetle carrying an ivory lotus seed", "pulse", "hop", 13, 71),
 ("焚页犀", "massive charcoal-paper rhino with a short bronze burning horn", "charge", "chase", 33, 69),
 ("讨名手", "large disembodied ivory paper hand wrapped in red knot strings", "grab", "blink", 23, 88),
 ("碎镜孩", "tiny angular black-and-ivory mirror child", "split", "retreat", 11, 122),
 ("笔杆武卫", "tall bamboo pen soldier with a bronze brush spear", "melee", "strafe", 20, 91),
 ("封愿墨兽", "huge squat black ink-paper boar carrying three ivory seals", "ink", "chase", 31, 49),
]
WEAPONS = [
 ("星灯针", "burst", "三段点射；最后一段双弹", 8, .48, 660, 570, 1),
 ("烟罗葫", "cloud", "烟团落地形成持续焚愿区域", 16, .70, 340, 480, 1),
 ("莲纹法轮", "orbit_blade", "环绕莲轮逐渐脱离并贯穿", 11, .52, 310, 420, 3),
 ("纸雨伞", "rain", "抛出纸伞，落点有三次纸雨", 17, .78, 390, 540, 1),
 ("铜纹弧灯", "lightning", "弧光射线串联最近的三名敌人", 20, .62, 0, 540, 1),
 ("八卦散烛", "radial", "八向射击，适合贴身清群", 9, .58, 490, 330, 8),
 ("墨潮笔", "wave", "宽幅摆动墨潮，穿透两名敌人", 14, .40, 520, 540, 1),
 ("牵魂铃", "tether", "持续绳束射线，近距离减速", 7, .16, 0, 380, 1),
 ("裂页弩", "split", "命中后向两侧分裂纸刃", 13, .44, 640, 620, 1),
 ("护灯盾", "boomerang_arc", "回旋盾有去程和回程伤害", 17, .65, 440, 430, 1),
 ("封愿地印", "mine", "埋下延迟爆炸法印，连片触发", 28, .84, 270, 290, 1),
 ("烛龙珠", "homing_cluster", "三枚追踪火珠，击中后小范围爆炸", 8, .55, 410, 560, 3),
 ("金线剑", "sweep", "大幅弧形剑气，带短距离推进", 25, .59, 0, 190, 1),
 ("裂空铜镜", "prism", "主射线与两道斜射线可叠加", 12, .66, 0, 660, 1),
 ("掌灯飞符", "guided_swarm", "按射击方向引导符群，逐渐会合", 7, .46, 420, 560, 4),
 ("长愿卷", "nova", "蓄力后释放扩张波环，沿障碍传播", 38, .98, 0, 240, 1),
]

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", "utf8")

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    PROMPTS.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((ROOT / "game/data/catalog.json").read_text("utf8"))
    def append(table, rows):
        added = {r["id"] for r in rows}
        catalog[table] = [r for r in catalog.get(table, []) if r["id"] not in added] + rows
    append("bosses", [{"id": f"b{i+6:02}", "name": n, "floor": 1, "health": 1150 + i % 5 * 135,
        "optional": i < 30, "fixed_heal_phase_indices": [1], "natural_ash": 30, "movement": m,
        "attack_family": a, "secondary_family": b, "size": 220 + i % 4 * 22, "radius": 35 + i % 4 * 4,
        "speed": 55 + i % 5 * 9, "phases": [a + "：明确预告与留空", b + "：移动后施法", "两种招式交替，恢复窗口保留"],
        "window": "施法后0.8秒", "unlock_condition": "随机层与试演", "art_brief": brief}
        for i, (n, brief, m, a, b) in enumerate(BOSSES)])
    append("enemies", [{"id": f"e{i+25:02}", "name": n, "floor": 1, "health": 30 + radius * 2,
        "speed": speed, "radius": radius, "render_size": 66 + radius * 2, "telegraph_ms": 550 + i % 3 * 100,
        "damage": 1, "pattern": attack, "movement": movement, "counterplay": "观察前摇；绕过攻击轴线再还击",
        "can_mark": True, "natural_ash": 8, "reward_once": True, "art_brief": brief}
        for i, (n, brief, attack, movement, radius, speed) in enumerate(ENEMIES)])
    append("weapons", [{"id": f"w{i+17:02}", "name": n, "mode": mode, "behavior": desc, "damage": damage,
        "interval_s": rate, "projectile_speed": speed, "range": reach, "pellets": pellets, "spread": .19,
        "pierce": 2 if mode in ["wave", "orbit_blade"] else 0, "mark_stacks": 1, "min_floor": 1, "max_floor": 11}
        for i, (n, mode, desc, damage, rate, speed, reach, pellets) in enumerate(WEAPONS)])
    append("obstacles", [{"id": key, "name": name, "behavior": description} for key, name, description in [
        ("powder_urn", "火药香瓮", "受击后短暂燃芯，爆炸伤及敌我，可连锁点燃旁边的瓮"),
        ("oil_lamp", "铜油灯", "受击爆炸，留下短时灼烧区域"),
        ("thorn_seal", "刺契机关", "朱印亮起后展开铜刺，触碰扣除心火"),
        ("bamboo_wall", "竹篱", "相连木质障碍，可被摧毁"),
        ("stone_wall", "残垣", "相连石质障碍，耐久较高"),
        ("rope_wall", "绳栅", "相连绳结障碍，可被摧毁")]])
    maps = [{"id": f"m{i+1:02}", **spec,
             "backgrounds": [f"res://assets/environment/expansion/m{i+1:02}_a.png", f"res://assets/environment/expansion/m{i+1:02}_b.png"],
             "enemy_ids": [f"e{25+(i*3+j)%32:02}" for j in range(8)] + [f"e{1+(i+j)%24:02}" for j in range(3)]}
            for i, spec in enumerate(THEMES)]
    expansion = {"version": 1, "campaign_floors": 11, "mid_boss": "b36", "final_boss": "b37",
        "boss_pool": [f"b{i:02}" for i in range(1, 36)], "biomes": maps,
        "story": [
            {"id": "opening", "title": "借来的灯", "lines": ["旧城每一个愿望，都在总账里借了一缕火。", "还清债的人消失了。名字被撕下，成了下一盏灯的灯芯。", "你带着一张空白愿页入夜，决定沿十一重旧账找回他们。"]},
            {"id": "reveal", "title": "第六重 · 守名判殿", "lines": ["守名大判守着一架永远不平的秤。", "他不是在收债。他把归还的名字藏起来，拖延总账的苏醒。", "要让所有人回来，你必须连自己的愿望也放上秤。"]},
            {"id": "ordeal", "title": "第七至十重 · 灯与影", "lines": ["判殿倒下，四重封契同时解开。", "每一重旧账都有两位守债者；他们争夺同一盏心灯。", "把路走完，才能回答：愿望属于许愿的人，还是记账的神？"]},
            {"id": "final", "title": "第十一重 · 万愿天穹", "lines": ["三十余间愿室悬在总账的空白页上。", "六道守债者的连门之后，最后一笔账等待你的名字。", "不是替所有人偿债，而是带他们重新做一次选择。"]},
            {"id": "ending", "title": "账尽，灯未灭", "lines": ["万愿总账的铜心裂开，旧城的名字像纸雨一样落下。", "你没有取得神的位子。你把空白愿页一张张还给夜归的人。", "纸童找回父亲的称呼，铃师听见真正的回声，灯客终于熄灭借来的火。", "傩面摘下面具，伞灵走出雨，墨吏写下第一行不需利息的字。", "此后，灯下仍有人许愿。愿望不再是一笔债。"]},
        ], "production_status": "authored; generated art and runtime evidence pending"}
    for table in ["relics", "weapons", "debt_contracts"]:
        for row in catalog[table]: row["max_floor"] = 11
    rules = json.loads((ROOT / "game/data/rules.json").read_text("utf8"))
    for floor in range(4, 12): rules["loot"]["rarity_by_floor"][str(floor)] = {"common": .15, "uncommon": .38, "rare": .39, "mythic": .08}
    rules["progression"]["level_thresholds"] = [20, 50, 90, 140, 200, 270, 350, 440, 540, 650, 770, 900, 1040, 1190, 1350, 1520, 1700, 1890]
    write(ROOT / "game/data/catalog.json", catalog)
    write(ROOT / "docs/incense-debt/data/catalog.json", catalog)
    write(ROOT / "game/data/rules.json", rules)
    write(ROOT / "docs/incense-debt/data/rules.json", rules)
    write(ROOT / "game/data/expansion.json", expansion)
    jobs = []
    references = ["output/imagegen/incense-debt/runtime/paper-temple-arena.png", "output/imagegen/incense-debt/characters-roster.png"]
    def job(name, brief, refs=references, background="opaque", layout=None, style=STYLE):
        prompt = PROMPTS / (name + ".txt")
        prompt.write_text(style + brief, "utf8")
        jobs.append({"name": name, "prompt": prompt.relative_to(ROOT).as_posix(), "output": (OUT / (name + ".png")).relative_to(ROOT).as_posix(),
                     "references": refs, "background": background, "size": "1536x1024", "layout": layout})
    for start in range(0, 20, 2):
        panel = []
        for biome in maps[start:start+2]:
            for index, variant in enumerate(["a", "b"]):
                panel.append(f"{biome['id']}_{variant}: {biome['environment']}. FLOOR: {biome['floor_material']}. PERIMETER SILHOUETTE: {biome['architecture']}. VARIANT: {biome['variants'][index]}.")
        job(f"themes-{start//2+1:02}", "EXACTLY 2 columns by 2 rows, four full room backgrounds, no panel gaps or borders. The two rows MUST have conspicuously different palettes, floor materials and perimeter silhouettes: each row is its own biome. Each panel is a complete rectangular overhead arena, with a large LOW-CONTRAST EMPTY playable center covering 80 percent of the panel, perimeter architecture at the outer edges, and visible north/south/east/west centered entry openings on the SAME walkable plane. Props only at the outer rim. Two variations of each biome differ in architecture and floor patterns. Do not draw actors or blocking objects in the playable center. Row-major panels: " + " | ".join(panel), refs=[references[1]], style=ROOM_STYLE, layout={"kind": "rooms", "ids": [p.split(":")[0] for p in panel], "columns": 2, "rows": 2})
    for table, start_id, count, ref in [("bosses", 6, 32, "bosses.png"), ("enemies", 25, 32, "paper-enemies.png")]:
        for chunk in range(4):
            rows = [r for r in catalog[table] if start_id+chunk*8 <= int(r["id"][1:]) < start_id+(chunk+1)*8]
            job(f"{table}-{chunk+1:02}", "EXACTLY four columns by two rows; eight COMPLETE isolated creatures on true transparent alpha, generous padding, no crossing grid boundaries, no frame or shadows outside the cell. Distinct silhouette and size; near top-down readable front. Row-major subjects: " + " | ".join(r["art_brief"] for r in rows), refs=["output/imagegen/incense-debt/runtime/" + ref, references[1]], background="transparent", layout={"kind": table, "ids": [r["id"] for r in rows], "columns": 4, "rows": 2})
    job("weapons", "EXACTLY four columns by four rows; sixteen distinct isolated weapon icons on true transparent alpha. Hand-made shrine implements, no text. Row-major subjects: " + " | ".join(n + ": " + d for n,m,d,*rest in WEAPONS), refs=["output/imagegen/incense-debt/runtime/weapons.png", references[1]], background="transparent", layout={"kind": "weapons", "ids": [f"w{i:02}" for i in range(17,33)], "columns": 4, "rows": 4})
    fx = ["amber_orb", "jade_needle", "paper_blade", "ink_wave", "lotus_petal", "ember_cluster", "smoke_cloud", "red_seal", "beam_amber", "beam_ink", "beam_thread", "beam_prism", "blast_flame", "blast_ink", "blast_lotus", "shockwave"]
    job("attack-fx", "EXACTLY four columns by four rows, sixteen isolated visual effects on true transparent alpha. Rich painterly texture, luminous paper fibers and irregular edges. No labels. Row-major: warm amber orb with smoky tail; jade hostile needle with sharp silhouette; torn ivory projectile blade; undulating charcoal ink wave; spinning jade lotus petal; three-point orange ember cluster; pale smoke puff; red folded seal; horizontal amber flame beam with white-hot core; horizontal ink brush beam with ragged ivory core; horizontal braided red thread beam; horizontal jade-gold prism beam; expanding amber fire explosion with ash shards; exploding ink lotus cloud; radiating ivory lotus bloom; broken bronze shockwave ring. Each subject centered and completely contained. Horizontal beams fully occupy their own cell width with endpoint space.", refs=[references[0], references[1]], background="transparent", layout={"kind": "fx", "ids": fx, "columns": 4, "rows": 4})
    props = ["powder_urn", "thorn_seal", "oil_lamp", "bamboo_wall", "stone_wall", "rope_wall", "broken_urn", "cold_thorn"]
    job("obstacles", "EXACTLY four columns by two rows, eight isolated environment props on true transparent alpha, overhead game view. Row-major: cracked ivory gunpowder incense urn with visible ember wick; low bronze spike trap surrounded by pointed red paper seals; explosive bronze oil lamp and black jar; modular rectangular wooden bamboo fence tile, endpoints can join; modular square aged stone shrine wall tile; modular bundled vermilion rope barricade tile; shattered ivory urn fragments; retracted bronze spike trap. Each subject centered; no characters, no floor, no lettering.", background="transparent", layout={"kind": "obstacles", "ids": props, "columns": 4, "rows": 2})
    scenes = ["the paper child arrives in the old lantern city carrying an empty prayer page", "lanterns burning over a jade river while torn names float upstream", "the colossal magistrate weighs a blank paper name on his bronze scale", "the magistrate breaks his own red seal to reveal imprisoned prayer names", "two shrine guardians confront the child between red curtains", "four old debt gates open along a long ivory paper bridge", "the vast ledger shrine appears against a red thread constellation", "six empty doors stretch toward a bronze heart altar", "the ledger deity opens its many arms over an empty prayer page", "the bronze heart breaks and torn ivory names descend like rain", "the six player characters return their blank prayer pages to the lantern city", "dawn over the old shrine, a small lamp remains lit beside a new blank page"]
    for chunk in range(3):
        job(f"story-{chunk+1:02}", "EXACTLY 2 columns by 2 rows, four cinematic narrative keyframes without gaps. Match the reference character identity exactly. Expressive scene lighting, layered paper stage depth, generous composition for camera pans; no text, no UI. Row-major: " + " | ".join(scenes[chunk*4:chunk*4+4]), layout={"kind": "story", "ids": [f"scene_{i+1:02}" for i in range(chunk*4,chunk*4+4)], "columns": 2, "rows": 2})
    production_path=ROOT / "docs/incense-debt/assets/expansion-production.json"
    for room_job in jobs:
        if room_job["layout"]["kind"] == "rooms":
            room_job["layout"]["rects"] = reviewed_room_rects(int(room_job["name"].rsplit("-", 1)[1]))
    previous=json.loads(production_path.read_text("utf8")) if production_path.is_file() else {"jobs":[]}
    preserved=[j for j in previous["jobs"] if j["name"].startswith("creatures-")]
    write(production_path, {"model": "gpt-image-2.5", "quality": "high", "jobs": jobs+preserved})
    print(json.dumps({"bosses": len(catalog["bosses"]), "enemies": len(catalog["enemies"]), "weapons": len(catalog["weapons"]), "biomes": len(maps), "room_backgrounds": 40, "production_jobs": len(jobs)}))

if __name__ == "__main__":
    main()
    # Re-authoring the base expansion must retain the now-required local rosters.
    from prepare_themed_encounters import main as prepare_themed
    prepare_themed()
