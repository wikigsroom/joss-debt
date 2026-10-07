# iOS 共享源码交接 / iOS shared-source handoff

本 Release 的 iOS ZIP 是可供实体 Mac 继续导出的共享工程，尚未创建 Xcode 工程、已签名 IPA 或真机验收记录。

The iOS ZIP is a shared project for export on a real Mac. An Xcode project, signed IPA, and physical-device acceptance are not included.

1. 下载并解压 `IncenseDebt-v0.1.0-alpha.1-ios-shared-source.zip`，保留 `game/` 和 `tools/` 的相对目录。
2. 在实体 macOS 安装 Xcode 与 Godot 4.7.2。
3. 从 Godot 官方获取匹配的 4.7.2 导出模板包，解出其中 `templates/ios.zip`，放到共享源码根目录 `.local-tools/export-templates-4.7.2/ios.zip`。该模板不在本 Release 的共享源码 ZIP 内。
4. 使用拥有者实际 Apple 开发团队的十位 ID 运行下方命令。
5. 在 Xcode 中打开生成的工程，选择团队与真实 iPhone / iPad，完成签名、构建和安装。

1. Download/extract `IncenseDebt-v0.1.0-alpha.1-ios-shared-source.zip`, retaining the relative `game/` and `tools/` layout.
2. Install Xcode and Godot 4.7.2 on a real macOS machine.
3. Obtain the matching 4.7.2 export-template package from Godot, extract `templates/ios.zip`, and place it at `.local-tools/export-templates-4.7.2/ios.zip` under the source root. The Apple template is not bundled in this release's source ZIP.
4. Run the command below with the owner's actual ten-character Apple development team ID.
5. Open the generated project in Xcode, choose the team and a real iPhone/iPad, then sign, build, and install.

```sh
python3 tools/runtime/export_ios_on_mac.py \
  --godot /Applications/Godot.app/Contents/MacOS/Godot \
  --team-id YOUR_ACTUAL_APPLE_TEAM_ID
```

自有应用标识可添加 `--bundle-id`。工程目标为 iOS 15.0 起、横屏、iPhone / iPad、Compatibility 渲染。对照当前十一层流程、20 主题、40 背景与 60/40 混编，验证双摇杆、第三指施术、安全区、旋转保护、存档恢复、文件选择、软键盘、剪贴板、帧率与热稳定，并记录真实设备结果。

Add `--bundle-id` for an owned application identifier. Targets are iOS 15.0+, landscape, iPhone/iPad, and Compatibility rendering. Validate the eleven-floor campaign, 20 themes, 40 backgrounds, mixed encounters, dual sticks, third-finger casting, safe areas, rotation guard, save recovery, file pickers, keyboard, clipboard, frame rate, and thermals. Record real-device results.

[原生导出脚本 / Native export script](https://github.com/wikigsroom/joss-debt/blob/v0.1.0-alpha.1/tools/runtime/export_ios_on_mac.py) · [官方模板 / Official matching templates](https://github.com/godotengine/godot/releases/tag/4.7.2-stable)
