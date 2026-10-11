"""Extend the reviewed optional-online policy to the implemented co-op campaign."""
from pathlib import Path
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
MODEL = ROOT / "docs/legal/privacy-policy-content.json"
SITE = ROOT / "sites/privacy-policy"


def main():
    policy = json.loads(MODEL.read_text("utf8"))
    if policy["policy_version"] == "1.5":
        print("Cooperative privacy model already 1.5")
        return
    if policy["policy_version"] != "1.4":
        raise RuntimeError("Expected reviewed policy 1.4")
    old_name = "incense-debt-privacy-policy-2026-10-11.docx"
    archive_name = "incense-debt-privacy-policy-2026-10-11-v1.4.docx"
    source = SITE / "downloads" / old_name
    archive = SITE / "downloads" / archive_name
    if archive.exists():
        if archive.read_bytes() != source.read_bytes():
            raise RuntimeError("Historical policy already exists with different bytes")
    else:
        shutil.copyfile(source, archive)
    html = (SITE / "versions/2026-10-11.html").read_text("utf8")
    html = html.replace(old_name, archive_name).replace('/versions/2026-10-11"', '/versions/2026-10-11-v1.4"')
    (SITE / "versions/2026-10-11-v1.4.html").write_text(html, "utf8")
    review_path = ROOT / ".local-tools/privacy-policy/visual-review.json"
    review = json.loads(review_path.read_text("utf8"))
    review["documents"][archive_name] = review["documents"][old_name].copy()
    review_path.write_text(json.dumps(review, ensure_ascii=False, indent=2) + "\n", "utf8")

    def extend(value):
        if isinstance(value, str):
            for before, after in [("0.3.0", "0.4.0"), ("双人对灯模式", "双人合作闯关及对灯切磋模式"), ("对战裁定", "战斗裁定"), ("实时对战", "合作闯关或对战"), ("对手", "队友或对手"), ("同一比赛", "同一联机房间"), ("对灯", "联机")]:
                value = value.replace(before, after)
            return value
        if isinstance(value, list): return [extend(item) for item in value]
        if isinstance(value, dict): return {key: extend(item) for key, item in value.items()}
        return value
    policy = extend(policy)
    policy["policy_version"] = "1.5"
    policy["scope"] = "Windows 与 Android 客户端 0.4.0 的离线模式、可选共灯合作闯关和对灯切磋模式，以及本隐私政策展示网页；旧版客户端请参阅对应历史政策"
    sections = {section["id"]: section for section in policy["sections"]}
    for block in sections["collection"]["blocks"]:
        if block.get("text", "").startswith("服务器在连接期间"):
            block["text"] = "服务器接收连接 IP、协议和内容版本、匿名身份、昵称（最多 16 字符）、角色／武器／技能配装、玩法模式、匹配或六位房间码、准备与成长选择、移动／瞄准／开火／技能／拾取和救援操作、心跳与事件确认，用于计算共享地图、怪物、掉落、金币、位置、伤害、个人构筑、救援、楼层或回合及结果。它保存恢复所需状态，分别记录合作结果和对战胜负计数，不接收您的离线愿簿或文件目录。"
        if block.get("text", "").startswith("匿名恢复凭据"):
            block["text"] = block["text"].replace("本场比分", "共享场景、救援状态及本场结果")
    for block in sections["storage"]["blocks"]:
        if block.get("text", "").startswith("联机状态保存在"):
            block["text"] += " 合作暂停时双方在线则不计断线期限；有人断线后重新计时 90 秒。"
    for block in sections["updates"]["blocks"]:
        if block.get("text", "").startswith("我们会公布"):
            block["text"] = "0.4.0 新增双人合作闯关，本次补充共享场景、怪物、掉落、成长、救援及合作结果的处理说明；对战模式仍可选。旧版客户端适用对应历史政策。后续新增处理功能时将先补充告知。"
        if block.get("text", "").startswith("本政策文字"):
            block["text"] = "本政策文字不会自行改变旧版客户端功能。我们保留已公开的历史文本供查询。当前为版本 1.5，本次补充可选合作闯关的信息处理说明，运营主体继续为 {{operator_name}}，与应用资料页保持一致。"
    MODEL.write_text(json.dumps(policy, ensure_ascii=False, indent=2) + "\n", "utf8")
    print("Optional co-op privacy model updated to 1.5; reviewed 1.4 archived")


if __name__ == "__main__":
    main()
