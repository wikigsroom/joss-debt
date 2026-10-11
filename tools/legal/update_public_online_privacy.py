"""Preserve policy 1.5 and describe the deployed optional official service."""
from pathlib import Path
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]

def main():
    model = ROOT / "docs/legal/privacy-policy-content.json"
    p = json.loads(model.read_text("utf8"))
    if p["policy_version"] == "1.6": return
    if p["policy_version"] != "1.5": raise RuntimeError("Expected reviewed policy 1.5")
    site = ROOT / "sites/privacy-policy"
    name = "incense-debt-privacy-policy-2026-10-11.docx"
    old = name.replace(".docx", "-v1.5.docx")
    archive = site / "downloads" / old
    if archive.exists(): raise RuntimeError("Refusing to overwrite policy history")
    shutil.copyfile(site / "downloads" / name, archive)
    html = (site / "versions/2026-10-11.html").read_text("utf8").replace(name, old).replace('/versions/2026-10-11"', '/versions/2026-10-11-v1.5"')
    (site / "versions/2026-10-11-v1.5.html").write_text(html, "utf8")
    review_path = ROOT / ".local-tools/privacy-policy/visual-review.json"
    review = json.loads(review_path.read_text("utf8"))
    review["documents"][old] = review["documents"][name].copy()
    review_path.write_text(json.dumps(review, ensure_ascii=False, indent=2) + "\n", "utf8")
    p["policy_version"] = "1.6"
    p["scope"] = "Windows 与 Android 客户端 0.5.0 的离线模式、可选官方共灯合作与对灯切磋，以及本隐私政策网页；旧版客户端适用对应历史政策"
    p["warm_notice"][0] = p["warm_notice"][0].replace("由您主动连接", "由您主动进入").replace("0.4.0", "0.5.0")
    p["warm_notice"][1] = "主菜单在共灯入口旁说明：官方服务位于新加坡，会传输昵称、匿名身份及游玩操作。您点击共灯后自动连接，断线期间自动重试；退出联机即停止连接。运营者为 {{operator_name}}，隐私联系邮箱 {{contact_email}}。联机处理仅用于匹配、战斗裁定、断线恢复及战绩；队友或对手可看到昵称、配装及对局状态。请勿填写真实身份信息。"
    sections = {s["id"]: s["blocks"] for s in p["sections"]}
    sections["collection"][7]["text"] = "Android 0.5.0 声明联网和振动普通权限，没有定位、通讯录、相机、麦克风、照片或广泛外部存储权限。联网在您主动进入共灯后自动启用；离开联机会停止连接及重试，不进入联机不影响离线模式。剪贴板和文件选择不等同于申请 Android 危险权限。"
    sections["collection"][17]["text"] = "0.5.0 使用固定的官方服务，由 {{operator_name}} 运营，运行于腾讯云新加坡区域的主机。联机界面不展示或提供修改服务器地址的功能。主菜单入口在连接前说明处理类别、境外所在地及退出方式，您点击可选共灯入口后自动建立加密连接；普通网络中断时按退避间隔自动重试，不在断线期间继续裁定战斗。身份失效或版本不匹配时提示您处理，不会擅自替换身份。"
    sections["collection"][19]["text"] = sections["collection"][19]["text"].replace("运营者另行配置的网络代理日志以其说明为准。", "官方站点和联机代理不记录访问日志；错误日志仅用于运行故障排查，可能包含连接 IP，不记录完整操作轨迹或恢复密钥。")
    sections["storage"][1]["text"] = "离线存档、设置、游玩日志及联机配置保存在您的设备上。Windows 默认位置为 %APPDATA%\\IncenseDebt；Android 使用应用数据目录。匿名联机身份、恢复凭据、昵称、配装、待确认请求和最近显示的战绩使用独立 online-client 目录。旧版保存的地址不会改变 0.5.0 的官方连接。单人三槽存档与联机身份分开保存。"
    sections["storage"][3]["text"] = sections["storage"][3]["text"].replace("联机状态保存在您选择的服务器，具体主机地区和运营者由该服务器提供者说明。随本版本提供的服务端默认", "官方联机状态保存在腾讯云新加坡主机，由 {{operator_name}} 管理。官方服务").replace("运营者自建的备份、代理日志或调整的参数需另行说明与管理。", "恢复检查点及身份文件仅限服务账号访问；不用于广告画像。代理故障日志滚动清理，最长保留 14 天。")
    sections["storage"][7]["text"] = "离线游玩不会自动向境外传输游戏文件。您主动进入共灯后，联机所需昵称、匿名身份、配装、房间及操作状态、连接 IP 由 {{operator_name}} 管理的新加坡官方主机处理，用于本政策第一章说明的匹配、战斗、恢复和战绩；不会传输您的离线愿簿。腾讯云提供基础设施托管，不向队友或对手公开恢复凭据。您可退出联机停止传输，或通过 {{contact_email}} 申请查阅、更正、删除服务端资料。新增境外接收方或改变用途时将另行告知，并依法履行所需程序。"
    sections["sharing"][0]["text"] = sections["sharing"][0]["text"].replace("您确认的服务器", "您主动启用的官方联机服务")
    for b in sections["third-parties"]:
        for row in b.get("rows", []):
            if row[0] == "您选择的联机服务器":
                row[:] = ["官方联机服务及腾讯云主机", "匹配、裁定、重连与战绩", "昵称、匿名身份、配装、房间、操作及对局状态；连接 IP", "{{operator_name}} 运营；腾讯云新加坡主机托管；https://cloud.tencent.com/document/product/301/11488"]
    sections["security"][1]["text"] = "官方客户端使用有效证书的 WSS 加密连接，保留证书和域名验证。服务端游戏端口仅监听主机回环地址，经 HTTPS 代理提供联机入口。请保护设备和本机恢复凭据，不公开分享 online-client 目录。服务器使用摘要保存凭据，检查点文件设置访问权限；这些文件并非另行加密，管理者需要持续保护主机及备份。"
    sections["rights"][5]["text"] = "我们无法远程读取、删除或恢复未提交给我们的离线文件。清除 online-client 可删除本机联机身份、配置和恢复凭据，但不会自动删除服务器已有昵称或战绩，并会失去原身份的恢复能力。联机大厅可查看当前身份的战绩；查阅、更正或删除官方资料请联系 {{contact_email}}，说明昵称、客户端版本、必要的房间或时间信息，以最少必要信息核验。不要公开发送恢复密钥。"
    sections["rights"][7]["text"] = sections["rights"][7]["text"].replace("拒绝连接服务器", "不进入共灯").replace("按其保存和删除规则", "按本政策的保存和删除规则").replace("对应运营者", "我们")
    sections["updates"][0]["text"] = "0.5.0 启用固定官方公网服务，主菜单说明新加坡处理位置和必要的信息类别；进入联机后自动连接，普通断线自动重试。本次同步补充官方运营主体、托管位置、保存期限及权利渠道。旧版客户端适用对应历史政策。"
    sections["updates"][2]["text"] = "本政策文字不会自行改变旧版功能。我们保留已公开历史文本供查询。当前为版本 1.6，运营主体继续为 {{operator_name}}，与应用资料页保持一致。1.5 历史文本可在 https://xhz.sidcloud.cn/versions/2026-10-11-v1.5 查询。"
    model.write_text(json.dumps(p, ensure_ascii=False, indent=2) + "\n", "utf8")

if __name__ == "__main__": main()
