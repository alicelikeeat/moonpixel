# 已知限制与路线图 / Known limitations

## 当前版本

- **平台**：只在 Linux + Godot 4.3（OpenGL 兼容渲染）下运行过。Windows / macOS / iOS / Android 导出均未验证，没有导出预设。
- **输入**：仅键鼠。没有触屏虚拟摇杆和手柄支持。
- **性能**：全部模拟在主线程。120–150 名村民在 64× 速度下每帧约 6 ms（开发机）；未在低端设备或移动设备上测量，也没有 30 分钟稳定性记录。
- **内存查询**：`OS.get_memory_info()` 在个别平台返回 −1，此时退回 256 MB 默认值，需要手动选择预算。
- **NPC**：村民始终画在地形之上（不会被树或墙遮挡）；只有异性伴侣会生育；没有疾病传播、战斗、贸易或村落间往来；离村落 3×3 区块以外的资源不会被利用。
- **地图**：勘测地图以区块为单位着色；没有道路连接村落；水面没有动画。
- **存档**：单一存档位；`index.json` 没有版本迁移。
- **音频**：没有。

## 仓库中存在但尚未交付的代码

以下模块来自 V1.0 总任务书的早期实现，**能编译，但没有接入可玩场景，也没有自动化测试**：

`game/combat/`、`game/player/`、`game/building/`、`game/crafting/`、`game/inventory/`、
`game/quests/`、`game/ecology/`、`game/entities/`、`game/npc/npc_service.gd`、
`game/bootstrap/simulation.gd`、`game_context.gd`、`game/world/world_service.gd`、`terrain/`、
`game/persistence/save_migrations.gd`，以及 `content/` 中的物品、配方、技能、敌人、任务数据。
`game/building/world_artisan.gd` 只是占位。

## 下一步

1. 把玩家建造工具接入无限世界（与村民共用 `set_tile` 入口）。
2. 村落间道路、贸易与通婚。
3. 触屏操作与移动端性能分级。
4. 把社会模拟和区块生成移到工作线程。
5. Windows 导出与 CI 构建产物。
