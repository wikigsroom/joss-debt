"""Check every generated source/crop/pose and produce reviewable contact sheets."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
PACKAGED = "--packaged" in sys.argv
REPORTS=ROOT/"docs/incense-debt/reports"/("platforms/windows" if PACKAGED else "runtime")/"expansion"
ASSETS=ROOT/"game/assets"
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    REPORTS.mkdir(parents=True,exist_ok=True)
    catalog=json.loads((ROOT/"game/data/catalog.json").read_text("utf8"))
    expansion=json.loads((ROOT/"game/data/expansion.json").read_text("utf8"))
    production=json.loads((ROOT/"docs/incense-debt/assets/expansion-production.json").read_text("utf8"))
    processed=json.loads((ROOT/"docs/incense-debt/assets/expansion-processed.json").read_text("utf8"))
    checks=[]
    def check(id,condition,detail=""):
        checks.append({"id":id,"passed":bool(condition),"detail":detail})
    check("specified_sub2_model",production["model"]=="gpt-image-2.5")
    check("all_sixty_four_boards_processed",processed["status"]=="processed" and processed["generated_jobs"]==64)
    check("processed_sources_match_current_production_queue",{r["source"] for r in processed["records"]}=={r["output"] for r in production["jobs"]})
    check("all_original_expansion_and_themed_actors",len(catalog["bosses"])==99 and len(catalog["enemies"])==296)
    check("sixteen_additional_weapons",len(catalog["weapons"])==32)
    check("twenty_biomes_each_two_backgrounds",len(expansion["biomes"])==20 and all(len(m["backgrounds"])==2 for m in expansion["biomes"]))
    revision=json.loads((ROOT/"game/assets/fx/combat-revision/manifest.json").read_text("utf8"))
    boundaries=json.loads((ROOT/"game/data/arena_boundaries.json").read_text("utf8"))
    check("forty_source_bound_inner_wall_contours",len(boundaries["rooms"])==40)
    for name,row in boundaries["rooms"].items():
        check("inner_wall_"+name,digest(ROOT/row["source"])==row["source_sha256"] and len(row["polygon"])==8)
    for row in revision["records"]:
        strip=Image.open(ROOT/row["path"]).convert("RGBA")
        frame_hashes=[hashlib.sha256(strip.crop((i*256,0,(i+1)*256,256)).tobytes()).hexdigest() for i in range(6)]
        check("revision_fx_"+row["id"],digest(ROOT/row["source"])==row["source_sha256"] and digest(ROOT/row["path"])==row["sha256"] and frame_hashes==row["frame_hashes"] and len(set(frame_hashes))==6)
    for row in processed["records"]:
        source=ROOT/row["source"]; path=ROOT/row["path"]
        check("crop_"+row["id"],path.is_file() and source.is_file() and digest(source)==row["source_sha256"] and digest(path)==row["sha256"])
    for animation in processed["animations"]:
        path=ROOT/animation["path"]; size=animation["frame_size"]; count=animation["frames"]
        strip=Image.open(path).convert("RGBA")
        frames=[strip.crop((i*size,0,(i+1)*size,size)) for i in range(count)]
        unique=len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames})
        check(animation["id"]+"_"+animation["state"],strip.size==(count*size,size) and digest(path)==animation["sha256"] and unique>=2,
              "distinct precomputed source-bound poses: "+str(unique))
        if animation["state"]=="death":check(animation["id"]+"_death_dissolves",np.asarray(frames[-1])[:,:,3].max()==0)
    rig=json.loads((ASSETS/"weapon-rig.json").read_text("utf8"))
    check("all_thirty_two_equipment_rigs",len(rig["weapons"])==32 and all((ROOT/"game"/spec["texture"].removeprefix("res://")).is_file() for spec in rig["weapons"].values()))
    for kind in ["bamboo_wall","stone_wall","rope_wall"]:
        check("connected_"+kind,all((ASSETS/f"obstacles/connected/{kind}/{i}.png").is_file() for i in range(16)))
    font=ImageFont.truetype(str(ASSETS/"fonts/NotoSansSC-Regular.otf"),18) if (ASSETS/"fonts/NotoSansSC-Regular.otf").exists() else ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",18)
    for table,start,count in [("bosses",5,32),("enemies",24,32),("weapons",16,16)]:
        sheet=Image.new("RGB",(1440,4*210 if count==32 else 2*210),(27,37,39)); draw=ImageDraw.Draw(sheet)
        for i,row in enumerate(catalog[table][start:start+count]):
            image=Image.open(ASSETS/table/(row["id"]+".png")).convert("RGBA")
            image.thumbnail((170,174),Image.Resampling.LANCZOS)
            x=i%8*180; y=i//8*210
            sheet.paste(image,(x+(180-image.width)//2,y+4),image)
            draw.text((x+7,y+179),row["id"]+" "+row["name"],font=font,fill=(216,231,219))
        sheet.save(REPORTS/(table+"-contact.png"))
    native=REPORTS
    for group in range(4):
        sheet=Image.new("RGB",(960,5*298),(27,37,39)); draw=ImageDraw.Draw(sheet)
        for i,biome in enumerate(expansion["biomes"][group*5:group*5+5]):
            for j,variant in enumerate(["a","b"]):
                path=native/f"environment-{biome['id']}-{variant}.png"
                if not path.is_file():path=ASSETS/f"environment/expansion/{biome['id']}_{variant}.png"
                sheet.paste(Image.open(path).convert("RGB").resize((480,270),Image.Resampling.LANCZOS),(j*480,i*298))
                draw.text((j*480+12,i*298+272),biome["id"]+" "+biome["name"]+" · "+variant,font=font,fill=(216,231,219))
        sheet.save(REPORTS/f"environments-contact-{group+1:02}.png")
    overview=Image.new("RGB",(1920,4*242),(27,37,39)); draw=ImageDraw.Draw(overview)
    palette_samples=[]
    for i,biome in enumerate(expansion["biomes"]):
        source=ASSETS/f"environment/expansion/{biome['id']}_a.png"
        path=native/f"environment-{biome['id']}-a.png"
        check("native_environment_"+biome["id"],path.is_file())
        im=Image.open(path if path.is_file() else source).convert("RGB")
        x=i%5*384; y=i//5*242
        overview.paste(im.resize((384,216),Image.Resampling.LANCZOS),(x,y))
        draw.text((x+8,y+219),biome["id"]+" "+biome["name"],font=font,fill=(216,231,219))
        rgb=np.asarray(Image.open(source).convert("RGB").resize((160,90)),dtype=float)/255
        palette_samples.append({"id":biome["id"],"mean_rgb":[round(float(n),4) for n in rgb.mean(axis=(0,1))],
            "palette":biome["palette"],"light_color":biome["light_color"],"floor_material":biome["floor_material"],"architecture":biome["architecture"]})
    overview.save(REPORTS/"twenty-themes-overview.png")
    for biome in expansion["biomes"]:
        creature_sheet=Image.new("RGB",(1280,650),(27,37,39)); d=ImageDraw.Draw(creature_sheet)
        # The top banner uses the matching source arena; the bottom displays every local actor.
        background=Image.open(ASSETS/f"environment/expansion/{biome['id']}_a.png").convert("RGB")
        creature_sheet.paste(background.resize((1280,220),Image.Resampling.LANCZOS),(0,0))
        d.text((14,12),biome["id"]+" "+biome["name"]+" · 独立遭遇池",font=font,fill=(255,255,255),stroke_width=2,stroke_fill=(22,28,31))
        check("theme_"+biome["id"]+"_twelve_mobs_and_three_to_seven_bosses",len(biome["enemy_ids"])==12 and len(biome["boss_ids"]) in [3,7])
        for i,identity in enumerate(biome["enemy_ids"]+biome["boss_ids"]):
            table="enemies" if identity.startswith("e") else "bosses"
            actor=Image.open(ASSETS/table/(identity+".png")).convert("RGBA")
            actor.thumbnail((126,150),Image.Resampling.LANCZOS)
            x=i%10*128; y=228+i//10*210
            creature_sheet.paste(actor,(x+(128-actor.width)//2,y),actor)
            row=next(r for r in catalog[table] if r["id"]==identity)
            d.text((x+4,y+155),row["name"],font=font,fill=(216,231,219))
        creature_sheet.save(REPORTS/("creatures-"+biome["id"]+"-contact.png"))
    check("twenty_independent_theme_definitions",len({m["palette"] for m in expansion["biomes"]})==20 and len({m["floor_material"] for m in expansion["biomes"]})==20 and len({m["architecture"] for m in expansion["biomes"]})==20)
    failures=[row["id"] for row in checks if not row["passed"]]
    report={"recorded_at":datetime.now(timezone.utc).isoformat(),"passed":not failures,"checks":checks,"failures":failures,
            "boards":64,"source_bound_crops":len(processed["records"]),"additional_animation_strips":len(processed["animations"]),
            "additional_animation_frames":sum(row["frames"] for row in processed["animations"]),
            "combat_revision_strips":len(revision["records"]),"combat_revision_generated_keyframes":revision["frames"],
            "environment_palette_measurements":palette_samples,
            "environment_review":"All 20 native theme pairs visually inspected for colour, floor material, silhouette and playfield legibility; mean RGB is descriptive data, not proof of aesthetic quality.",
            "scope":"all generated sources/crops, distinct baked pose frames and equipment rigs; native interaction and full combat evidence are separate reports"}
    if PACKAGED:
        native_report=json.loads((REPORTS/"expansion-native.json").read_text("utf8"))
        report["artifact_sha256"]=native_report.get("artifact_sha256")
        if not native_report.get("passed") or digest(ROOT/"build/windows/IncenseDebt.exe") != report["artifact_sha256"]:
            report["passed"]=False; report["failures"].append("current_packaged_native_evidence")
    (REPORTS/"expansion-assets.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf8")
    print(json.dumps({"passed":report["passed"],"checks":len(checks),"failures":report["failures"]},ensure_ascii=False))
    return int(not report["passed"])
if __name__=="__main__":raise SystemExit(main())
