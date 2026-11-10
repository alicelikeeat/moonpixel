# 架构总览 / Architecture

```
game/
  bootstrap/   mp.gd 常量与哈希 · loc.gd 本地化 · main.gd 启动界面
  assets/      content_registry.gd 数据注册表 · pixel_art.gd 程序化美术
  platform/    memory_budget.gd 设备内存查询
  world/       open_world.gd 无限世界 · generation/ 生成器 · chunks/ 区块数据
  npc/         agent.gd · settlement.gd · society.gd 自主 NPC 社会
  ui/          open_world_view.gd 可玩场景与 HUD
  persistence/ save_service.gd 原子写入
content/       JSON 数据：地块、生物群系、物品、配方……（数值 id 是存档契约）
tests/         无依赖的 headless 测试
tools/         开发工具（普查、地图渲染、带超时的运行脚本）
```

## 原则

- **逻辑与表现分离**：`OpenWorld`、`Society` 是不依赖场景节点的 `RefCounted`，可以无界面运行和测试；
  `OpenWorldView` 只读取状态并转发输入。
- **数据驱动**：地块、生物群系等由 `content/*.json` 定义，`ContentRegistry` 加载时做交叉引用校验。
- **确定性**：世界生成只用整数哈希和带种子的噪声；社会模拟使用带种子的 RNG。
- **世界写入单一入口**：所有地块修改都经过 `OpenWorld.set_tile()`，它负责脏标记、生长计时器和事件。
- **线程边界**：当前全部在主线程；`InfiniteGenerator.generate()` 不触碰共享可变状态，可以安全移到工作线程。

## 当前接入可玩场景的模块

`MemoryBudget → OpenWorld → Society → OpenWorldView`。

仓库中另有固定尺寸世界（`WorldPlan` / `ChunkGenerator` / `WorldService`，有测试）以及
战斗、建造工具、物品、任务等模块（能编译、未接入、无测试），见 [已知限制](../known-limitations.md)。
