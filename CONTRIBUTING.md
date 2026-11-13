# 参与贡献

- 语言：Swift 5.9+，4 空格缩进。核心逻辑放在 `ios/Sources/MoonPixelCore`（不依赖 UIKit，可在 Linux 上测试），界面放在 `ios/App`。
- 提交前运行 `cd ios && swift test -c release -Xswiftc -enable-testing`。
- 平衡参数只改 `RealmConfig`，并重新生成 `docs/PARAMETERS.md`。
- 修改 `content/` 下的 JSON 后运行 `python3 tools/gen_swift_content.py`。
- 只提交你有权使用的素材。
