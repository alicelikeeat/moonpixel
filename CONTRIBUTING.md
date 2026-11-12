# 贡献指南 / Contributing

- 引擎：Godot 4.5，GDScript，Tab 缩进。
- 游戏逻辑写成不依赖场景节点的 `RefCounted` 类，并为它补充 `tests/test_*.gd`。
- 修改世界只通过 `OpenWorld.set_tile()`；不要直接改 `ChunkData.layers`。
- `content/tiles/tiles.json` 中的数值 id 是存档契约，只能新增，不能重编号或复用。
- 提交前运行 `tools/gd.sh 600 tests/run_tests.gd`，测试失败不得合并。
- 性能相关改动请附上 `tools/society_sim.gd` 或测试输出作为前后对比。
- 不要提交授权不明的美术或音频素材；本项目的美术全部由 `game/assets/pixel_art.gd` 程序生成。
- 不得通过删除用户存档来解决兼容问题。
