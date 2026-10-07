# 《香火债》原生 iOS 交接

本目录是共享工程与导出准备，尚未创建 Xcode 工程、签名 IPA 或完成真机测试。

解压 IncenseDebt-shared-source.zip，保留 game/ 与 tools/ 的目录关系。将随工作区提供的 .local-tools/export-templates-4.7.2/ios.zip 放到解压目录的相同位置。Godot 与模板锁定为 4.7.2；工程使用 Compatibility、横屏、iPhone/iPad 和 iOS 15.0 起的目标规格。

在真实 Mac 安装 Xcode 与 Godot 4.7.2 后运行：

```sh
python3 tools/runtime/export_ios_on_mac.py --godot /Applications/Godot.app/Contents/MacOS/Godot --team-id "$APPLE_DEVELOPMENT_TEAM_ID"
```

APPLE_DEVELOPMENT_TEAM_ID 必须是拥有者实际开发团队的十位 ID。若需自有应用标识，增加 --bundle-id 参数。脚本仅生成 Xcode 工程；随后在原生 Xcode 选择自己的团队和真实设备，完成签名、构建及安装。发布到商店不在该脚本内。

真机验收：从初始纸童开始完整十一层，包括第六层固定首领、第七至十层双首领、第十一层连续六首领与结尾；核对20套地图与专属怪物池、40张房间背景；解锁六名角色；双摇杆与第三指施术；刘海安全区；后台存档与过场恢复；系统返回；普通房、精英和 Boss 的持续帧率与热稳定。所有结论登记在平台报告中，不使用模拟器或虚拟环境替代。

官方要求：https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
