"""Add 12 map-specific mobs and 3+ bosses per biome with real Sub2 source jobs."""
from pathlib import Path
import json
from themed_encounters import build_encounters

ROOT=Path(__file__).resolve().parents[2]

def write(path, value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n","utf8")

def main():
    enemies,bosses,pools=build_encounters()
    catalog=json.loads((ROOT/"game/data/catalog.json").read_text("utf8"))
    for table, added in [("enemies",enemies),("bosses",bosses)]:
        identities={row["id"] for row in added}
        catalog[table]=[row for row in catalog[table] if row["id"] not in identities]+added
    expansion=json.loads((ROOT/"game/data/expansion.json").read_text("utf8"))
    expansion["themed_encounters_version"]=1
    for biome,pool in zip(expansion["biomes"],pools):biome.update({key:value for key,value in pool.items() if key!="id"})
    write(ROOT/"game/data/catalog.json",catalog);write(ROOT/"docs/incense-debt/data/catalog.json",catalog)
    write(ROOT/"game/data/expansion.json",expansion)
    write(ROOT/"docs/incense-debt/data/rules.json",json.loads((ROOT/"game/data/rules.json").read_text("utf8")))
    manifest=json.loads((ROOT/"docs/incense-debt/assets/expansion-production.json").read_text("utf8"))
    prior_jobs={job["name"].removesuffix("-02"):job for job in manifest["jobs"] if job["name"].startswith("creatures-")}
    manifest["jobs"]=[job for job in manifest["jobs"] if not job["name"].startswith("creatures-")]
    style="MANDATORY ATLAS SPACING: Each complete figure must fit within the central 65 percent of its own cell width and height. At least 60 transparent pixels of empty space around every figure. No opaque connection between figures; no shared poles or overlapping ribbons. Binding Incense Debt character style: tactile fibrous paper, woodblock ink contours, matte cut-paper puppet silhouettes, near-top-down gameplay front view, upper-left lighting. Match the ENVIRONMENT reference palette and physical materials; do not impose red ribbons on every creature. No text, no UI, no floor, no opaque background. Truly transparent alpha. Each figure complete and isolated, generous margins, no overlaps, no crossing cell boundaries. "
    for biome in expansion["biomes"]:
        for kind,rows in [("enemies",[r for r in enemies if r["theme"]==biome["id"]]),("bosses",[r for r in bosses if r["theme"]==biome["id"]])]:
            columns,lines=(4,3) if kind=="enemies" else ((3,2) if len(rows)==6 else (2,2))
            brief=f"EXACTLY {columns} columns by {lines} rows, {columns*lines} separate cells. Row-major creatures below. Very different wide/narrow/tall/small/large silhouettes within the same thematic family. Visible light paper edges and dark contour make bodies readable over this reference arena. "
            if kind=="bosses":brief+="These bosses are much larger and more monumental than ordinary monsters; do not draw small companion figures. "
            subjects=[row["art_brief"] for row in rows]
            subjects += ["EMPTY fully transparent unused cell; no subject"]*(columns*lines-len(subjects))
            name="creatures-"+biome["id"]+"-"+kind
            prior=prior_jobs.get(name,{})
            prompt=ROOT/"docs/incense-debt/assets/prompts/expansion"/(name+".txt")
            prompt.write_text(style+brief+" | ".join(subjects),"utf8")
            manifest["jobs"].append(dict(name=prior.get("name",name),prompt=prompt.relative_to(ROOT).as_posix(),
                output=prior.get("output",f"output/imagegen/incense-debt/expansion/{name}.png"),
                references=[biome["backgrounds"][0].replace("res://","game/"),"output/imagegen/incense-debt/characters-roster.png"],
                background="transparent",size="1536x1024",layout=dict(kind=kind,ids=[r["id"] for r in rows],columns=columns,rows=lines)))
    write(ROOT/"docs/incense-debt/assets/expansion-production.json",manifest)
    rows=["# 二十主题遭遇池 · 每图十二种小怪与主题首领","",
          "普通主题每图12种小怪、3名Boss，共15种独立角色。判殿含两名专属Boss和守名大判；天穹含6名连续关卡守卫与万愿总账，共19种。两种房间背景共享所属主题池，精英与召唤也从本主题池选取。旧图鉴稳定ID保留供兼容存档与试演，正式随机地图使用对应主题内容。","",
          "| 主题 | 十二种小怪 | 主题Boss |","| --- | --- | --- |"]
    by_id={r["id"]:r["name"] for r in catalog["bosses"]+catalog["enemies"]}
    for biome in expansion["biomes"]:rows.append("| "+biome["name"]+" | "+"、".join(by_id[i] for i in biome["enemy_ids"])+" | "+"、".join(by_id[i] for i in biome["boss_ids"])+" |")
    rows += ["","所有新增角色板均用指定 Sub2 模型参考所属地图和纸偶设定生成，完整剪影提取后制作运动、攻击、预告、受击与消散帧。主题关系在 expansion.json 内以稳定ID明示；首领主线、双首领、六连房均由十二位种子从所属主题池派生。","","图鉴美术完整性、每主题12个小怪和3—7个Boss、正式生成与召唤不混入其他主题，由原生图像检查与规则测试共同验证。生成状态另存 assets/expansion-generation-status.json，不以排队成功代替成品素材。",""]
    (ROOT/"docs/incense-debt/25-themed-encounters.md").write_text("\n".join(rows),"utf8")
    print(json.dumps(dict(additional_themed_enemies=len(enemies),additional_themed_bosses=len(bosses),total_enemies=len(catalog["enemies"]),total_bosses=len(catalog["bosses"]),jobs=len(manifest["jobs"]))))
if __name__=="__main__":main()
