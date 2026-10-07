"""Author equipment data and prompts; image generation uses the named Sub2 skill."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/imagegen/incense-debt/equipment-polish"

ACTIVE = [
    ("a01", "火签筒", "bombs", 3, "向瞄准方向抛出三枚延迟火签，逐段爆发。", "an open brass incense cylinder with three red burning paper sticks"),
    ("a02", "归心灯", "heal", 6, "恢复2心火；满血时不消耗充能。", "a tiny ivory paper lantern with a jade heart flame"),
    ("a03", "无债铜镜", "mirror", 4, "短暂护身并反射周围敌弹。", "a round antique bronze mirror with an ivory knotted reflection"),
    ("a04", "墨砚", "ink_field", 4, "铺下墨池，持续伤害并减速恶愿。", "a black inkstone with a turquoise ink whirl"),
    ("a05", "红线卷", "thread_beams", 3, "朝前织出五道贯穿红线，兼容爆炸供物。", "a spool of crimson ritual thread with five luminous loose ends"),
    ("a06", "纸鹤匣", "seekers", 3, "放出追踪纸鹤；兼容散射与命中修饰。", "an ivory folded box carrying three angular burning paper cranes"),
    ("a07", "引灰铃", "ash_bell", 2, "收拢香灰、纸钱，并恢复20香火。", "a small bell of aged brass with a pale smoke ribbon"),
    ("a08", "莲台印", "lotus_guard", 5, "生成跟随身边的莲印，护身并持续扫荡。", "a jade lotus stamp with a red lacquer wooden handle"),
    ("a09", "转愿骰", "reroll_ground", 6, "重掷当前房内未拾取的装备；无装备时不消耗。", "an ivory rounded dice wrapped in a red string bow"),
    ("a10", "停雨符", "freeze", 4, "消除周围敌弹并短暂冻结普通恶愿。", "an ice blue vertical paper talisman with a snowflake seal"),
    ("a11", "风行履", "haste", 3, "短时提升移速与攻速，并缩短身法冷却。", "a tiny vermilion cloth shoe with jade wind feathers"),
    ("a12", "雷霆签", "chain_lightning", 6, "释放三轮跳跃雷签，逐个追击邻近目标。", "three electric violet paper tickets with white forked lightning"),
]
TRINKETS = [
    ("tr01", "铜钱坠", "damage", .15, "伤害 +15%", "one old pierced brass coin pendant"),
    ("tr02", "灯芯扣", "fire_rate", .18, "攻速 +18%", "a tiny glowing orange wick buckle"),
    ("tr03", "羽铃", "move_speed", .12, "移速 +12%", "a jade feather attached to a brass bell"),
    ("tr04", "墨尺", "range", .25, "射程 +25%", "a dark blue carved ink ruler"),
    ("tr05", "风串", "shot_speed", .20, "弹速 +20%", "three cream beads strung with a turquoise wind tassel"),
    ("tr06", "玉珠", "crit", .08, "暴击率 +8个百分点", "one jade spherical bead with a white star glint"),
    ("tr07", "红珀", "blast_radius", .28, "爆炸半径 +28%", "a faceted orange-red amber shard"),
    ("tr08", "铜环", "beam_width", .32, "射线宽度 +32%", "a thick worn brass ring with luminous ivory inner edge"),
    ("tr09", "小莲", "pickup_radius", .35, "香灰拾取范围 +35%", "a miniature jade lotus ornament"),
    ("tr10", "福袋", "luck", .25, "稀有掉落概率 +25%", "a small red cloth lucky pouch with a pale paper knot"),
    ("tr11", "丝穗", "charge_efficiency", .50, "清房充能 +50%（余数保留）", "a golden tassel bound with red thread"),
    ("tr12", "纸扣", "knockback", .20, "主攻击击退 +20%", "a cream folded paper butterfly buckle"),
]
MODS = [
    ("r55", "三叠灯", "spread", 3, "主攻击至少三发散射；多档散射取最高档。", "three small ivory paper lamps arranged in a fan", "common"),
    ("r56", "四方纸", "spread", 4, "主攻击至少四发散射；适用于射线。", "four overlapping rectangular red paper seals in a fan", "uncommon"),
    ("r57", "五瓣签", "spread", 5, "主攻击至少五发散射；适用于爆炸与射线。", "five jade paper petals forming a five-point fan", "rare"),
    ("r58", "爆香核", "explosive", 1, "命中或终点触发一次爆香；射线也保留爆炸。", "a dark brass orb with a fiery orange cracked center", "uncommon"),
    ("r59", "光墨匣", "beam", 1, "将弹道改为射线，保留散射、爆香、蓄力与追踪。", "a jade ink prism with an ivory luminous beam", "rare"),
    ("r60", "弯月钉", "pierce", 2, "弹道穿透 +2；射线获得更远射程。", "two crescent shaped ivory ritual nails", "common"),
    ("r61", "寻愿蝶", "homing", 1, "弹道向附近目标追踪；射线朝瞄准扇区内目标修正。", "a folded pale jade paper moth with red eyes", "uncommon"),
    ("r62", "浮光绳", "controlled", 1, "飞行弹道跟随瞄准方向；散射保留各自偏角。", "a luminous ivory ribbon knotted around red thread", "uncommon"),
    ("r63", "回音折", "bounce", 1, "增加一次反弹；射线在墙边折返。", "an angular red paper arrow bent into a sharp echo", "uncommon"),
    ("r64", "雨花纸", "split", 1, "首次落点裂出两片纸锋；子代不再次分裂。", "two fluttering ivory torn paper shards with lotus marks", "uncommon"),
    ("r65", "长明炭", "linger", 1, "爆炸或射线落点留下短暂火场。", "a black incense charcoal cube with red glowing pores", "rare"),
    ("r66", "蓄月珠", "charge", 1, "主攻击短时蓄力，强化伤害、爆炸和射线宽度。", "a silver jade moon pearl cupped in a red paper crescent", "rare"),
]
FAMILIES = [
    ("ember", "amber incense sparks, layered tongues of orange flame, cracked charcoal embers"),
    ("ink", "deep navy ink splashes, calligraphic black brush strokes, luminous cyan ink droplets"),
    ("thread", "crimson braided red strings, tied gold knots, frayed ivory fiber wisps"),
    ("prism", "jade prismatic crystals, angular white glass refractions, mint triangular shards"),
    ("lotus", "pink and ivory lotus petals, layered golden pollen, pale jade lotus veins"),
    ("smoke", "silver incense smoke, soft charcoal plumes, torn ivory ash flakes"),
    ("frost", "icy blue snowflake spokes, jagged white ice spines, cold drifting pale frost dust"),
    ("storm", "forked violet-white lightning, jagged electrical arcs, short lavender sparks"),
    ("void", "dark violet torn paper holes, thin ivory crescent edges, black star fragments"),
    ("brass", "burnished brass ritual cog rings, segmented gold metal shards, pale yellow glints"),
]

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", "utf8")

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    data = {"version": 1, "active_items": [], "trinkets": [], "relics": [],
            "rare_drops": {"normal": .008, "elite": .025, "boss": .08, "room": .035,
                           "weights": {"battery": 35, "active": 20, "trinket": 30, "modifier": 15}}}
    for id, name, effect, charge, behavior, _ in ACTIVE:
        data['active_items'].append(dict(id=id, name=name, effect=effect, charge_rooms=charge,
            behavior=behavior, icon=f"res://assets/active_items/{id}.png", min_floor=1, max_floor=11))
    for id, name, stat, value, behavior, _ in TRINKETS:
        data['trinkets'].append(dict(id=id, name=name, stat=stat, value=value, behavior=behavior,
            icon=f"res://assets/trinkets/{id}.png", min_floor=1, max_floor=11))
    for id, name, effect, value, behavior, _, rarity in MODS:
        data['relics'].append(dict(id=id, name=name, routes=['ink','fire'], rarity=rarity, stack_limit=1,
            trigger='attack_recipe', modifier=effect, modifier_value=value, behavior=behavior,
            min_floor=1, max_floor=11, proc_policy=dict(primary_only=True,secondary_can_proc=False,
            max_generation_depth=1,once_per_target_per_pulse=True), implementation_status='implemented'))
    write_json(ROOT/'game/data/equipment.json',data)
    write_json(ROOT/'docs/incense-debt/data/equipment.json',data)
    prompts=OUT/'prompts';prompts.mkdir(exist_ok=True)
    art_style = ('Original Incense Debt game asset, elegant hand-cut paper and ink illustration, ivory paper edges, '
        'subtle tactile fibers, deep dark contours, aged brass, jade, vermilion accent. Modern readable game icon, '
        'orthographic front/top view, bold silhouette at 48 pixels, no writing, no letters, no watermark, no UI. ')
    jobs=[]
    for kind, rows, column in [('active_items',ACTIVE,5),('trinkets',TRINKETS,5),('modifiers',MODS,5)]:
        subjects='; '.join(f'row {i//4+1} column {i%4+1}: {row[column]}' for i,row in enumerate(rows))
        prompt=art_style+'A precise sprite atlas of TWELVE separate equipment icons in FOUR equal columns and THREE equal rows. Every item isolated and centered in its own cell with wide transparent gutters. Transparent alpha background. No cast shadows extending into adjacent cells. Exactly these subjects: '+subjects
        path=prompts/(kind+'.txt');path.write_text(prompt,'utf8')
        jobs.append(dict(id=kind,prompt=str(path),output=str(OUT/(kind+'.png')),kind='equipment'))
    for family,material in FAMILIES:
        for group in ['beams','areas']:
            rows = ['straight flowing ritual lance with a sharp luminous core','braided double helix tether with knots','wide crescent wave with cut-paper ribbons','forked zigzag lightning branches'] if group=='beams' else ['spherical erupting blast with torn fragments','thin expanding shock rings with spokes','spiral peeling paper vortex with curved shreds','flat ritual seal field with outward orbiting petals']
            progression = ('For beams: six real animation keyframes: compact charge, emerging front, full ignition, flowing stable body, dispersing impact shards, curling afterglow. ' if group=='beams' else 'For areas: six real animation keyframes: tiny anticipation, rapid swelling, full-radius burst, expanding broken rim, scattered debris, dissipating embers. ')
            prompt=(art_style+'Create a game VFX sprite sheet, exactly FOUR horizontal rows by SIX columns, each cell 256 by 256 in a 1536 by 1024 canvas. '
                'Transparent alpha background. This family uses '+material+'. Each row is one unique effect with its own physical structure. '
                +'; '.join(f'row {i+1}: {shape}' for i,shape in enumerate(rows))+'. '+progression+
                'Keep identical centered anchors and scale within each row; stages must visibly evolve, never duplicate frames. '
                'All silhouettes stay inside their own cell with at least 12 pixels transparent gutter; maximum radii and beam length 110 pixels. '
                'Beams oriented horizontally from left to right. High contrast dark contour and bright paper core. '
                'No lettering, no diagrams, no cell borders, no backdrop, no full-screen flash. Handcrafted graceful intensity, not photoreal fire.')
            name=f'{family}-{group}';path=prompts/(name+'.txt');path.write_text(prompt,'utf8')
            jobs.append(dict(id=name,prompt=str(path),output=str(OUT/(name+'.png')),kind='fx',family=family,group=group))
    write_json(OUT/'jobs.json',jobs)
    print(json.dumps({'active_items':12,'trinkets':12,'attack_modifiers':12,'art_jobs':len(jobs),'generated_fx_target':80,'keyframe_target':480}))

if __name__=='__main__':main()
