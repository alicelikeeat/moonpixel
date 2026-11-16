# MoonPixel 世界核心：现状、状态所有者与组合方式

本文对应“可组合世界核心”任务。审计基线是分支 `claude/upbeat-gates-vu0ssd` 上 `a763549`（v2.2 之后又加了可靠性一轮和无限国度），不是 v2.2 快照。

## 1. 开工审计：现状 → 本轮之后

| 领域 | 审计时的状态 | 本轮之后 |
|---|---|---|
| 内容定义 | 三套互不相通的表：开放世界 `Recipe`/goods（`Economy.swift`）、文明层 `CivItem`/`CivRecipe`/`CivUnitDef`（数组和字典，键是裸字符串）、指挥模式 `SkKind`（按数组位置索引） | 文明层内容进入 `ContentRegistry`：带命名空间的键（内置为 `moonpixel:`，存档里写裸键以兼容旧档），JSON 内容包，整包校验。开放世界和指挥模式的表**仍未迁入**（见第 7 节） |
| 单位原型 | `CivUnitDef` 是一个 30 个字段的平铺结构，规则里有 `def.hangar > 0` 之类的判断 | 原型由能力组成：移动、油箱或动力、船体与关键部位、乘员、储存、散热、探测、武器、机库、飞行。只保存具备的能力；规则只问“有没有机库”，不问“是不是航母” |
| 世界操作 | 面板直接调用 `c.build/order/send/deploy`，没有去重 | 一律通过 `WorldCommand` → `Civ.execute`：校验、预留、执行或拒绝、`CommandResult`；同一编号只执行一次；可指定执行步和城市修订号；去重窗口（4096 条）和待执行命令随存档保存 |
| 预留 | `CivCity.reserved` 字段存在但从未使用 | 下单时为下一段预留材料，开工时使用，取消或城市失守时释放；每日审计检查“城市预留 = 各项目持有之和 ≤ 库存” |
| 运输 | 目的地易主后货物会交给新主人 | 车队记住收货国；收货城易主则返回出发城或最近的本国城市 |
| 库存事务 | 每个模式各写一遍“检查够不够、再逐项扣除” | `Goods.take/move`（全成或全不成），统一用于城镇库存、玩家背包、区域城市（只认可用量）、指挥模式阵营资金 |
| 伤害 | 指挥模式和区域战争各自乘 `vs[armor]` | `Combat.damage` 与 `Combat.wear` 两种模式共用 |
| 存档 | 开放世界：分代存储 + `SaveCoordinator`；都市：上一轮已改成原子 `SaveFile`；指挥对局：`SaveFile`；文明层：随世界快照 | 不变，并已复用：文明层按编号排序写出、缺字段取默认、拒绝更新版本；内容规则（`CivConfig`）不进存档 |
| 渲染是否改写权威状态 | 2D `GameScene` 与 3D `SolidRenderer` 只读 `Society`；指挥模式的 `CommandScene` 通过 `SkirmishSession` 下命令；3D 的网格烘焙在后台用快照、带版本，过期结果会丢弃 | 不变。尚无统一的 `RenderSnapshot` 类型（见第 7 节） |
| 固定三国 | 已在上一轮清除（`docs/CIV.md`） | — |

## 2. 状态所有者（每样事实只有一个写者）

| 事实 | 唯一所有者 | 读者 |
|---|---|---|
| 地块、区块、修订号 | `OpenWorld`（`World.swift`） | Society、2D/3D 渲染、文明层的地区勘测（只读生成器） |
| 附近城镇的居民、建筑、库存、军团 | `Society`（`Society.swift`、`Realm.swift`、`War.swift`） | 文明层桥接（只读，映射为 `detail` 城市） |
| 国家注册表与编号计数器 | `Civ.polities` + `Civ.nextNation`；`Realm.nations` 是附近国家的详细状态，ID 与之共用 | 面板、Society |
| 区域城市的人口、库存、设施、预留 | `CivCity`（`Civ.swift`） | 面板（只读）；修改只经命令或日结 |
| 行程中的人和货 | `CivTrip` | — |
| 部队、装备、打击、情报 | `CivForce`、`CivUnit`、`Civ.strikes`、`Civ.intel`（`CivWar.swift`） | 面板 |
| 内容定义 | `ContentRegistry.shared`（启动时设定，之后只读） | 所有规则 |
| 都市城市 | `Metro`（独立存档 `metro.json`） | `MetroScene` |
| 指挥对局 | `Skirmish`（独立存档 `battle.json`） | `CommandScene` |
| 已执行命令 | `Civ.commandResults` | — |

## 3. 依赖方向

```
Presentation (App/: SpriteKit, RealityKit, Metal, SwiftUI)
      │ 读快照 / 发命令
      ▼
ModeAdapters  ── GameModel、SkirmishSession、MetroSession、CivPanel（命令 → Civ.execute）
      │
      ▼
Polity / Population / Economy / UnitsCombat   （Civ*.swift：同一个 Civ 对象内按文件分职责）
      │            │
      │            ├── Services.swift：Goods（库存事务）、Combat（伤害）
      │            └── Commands.swift：命令、结果、预留
      ▼
ContentRegistry（Registry.swift + CivData.swift 内置包 + content/packs/*.json）
      │
      ▼
WorldKernel / SpatialWorld（Core.swift、World.swift、Frame.swift：ID、时间、区块、生成器、调度队列）
Persistence（Store.swift、SaveCoordinator、SaveFile.swift）── 只保存与恢复，不修正经济
```

核心库 `MoonPixelCore` 不依赖 UIKit、SpriteKit、RealityKit，全部测试在 Linux 无界面运行。

## 4. 时钟与调度

- 世界时钟：`OpenWorld.time`（游戏秒）。Society 每 `Society.hour` 一步；文明层同一时钟，每小时一步。
- 每小时：先执行到期命令，再落下到期打击、移动、能量、空中作业、探测、战斗、占领，然后过完“这个小时”的那批城市的一天（城市编号 mod 24）。
- 每天：国家（关系、科研、叛离、合并、决策）、行程、工业、部队补给。
- 指挥模式：固定 1/20 秒步；都市：按天推进。三者时间互不换算，指挥对局和都市城市都不从世界借资产（见第 7 节）。

## 5. 如何加内容（不改规则代码）

内容包是 JSON，键必须带包自己的前缀。示例 `content/packs/example-cannery.json`（测试 `RegistryTests` 直接加载这个文件）：

- 新食物 `example:canned_fish`（营养、保质期、需要的科技）；
- 新设施 `example:cannery`（成本、工人、能源）；
- 新配方 `example:can_fish`（鱼 + 木材 → 罐头）：城市有罐头厂就会开工，罐头和其他食物一样进入粮食账、被吃掉、会腐坏；
- 新载具变体 `example:great_carrier`：以 `moonpixel:carrier` 为底，只改机库（20 架、每小时 6 架次）、乘员和造价，其余能力继承。下单、分段扣料、配员、舰载机上舰都用原有规则。

加载：`ContentRegistry.shared = try ContentRegistry.builtin().adding(data)`。整包一起校验，失败时什么都不加入，并列出每个问题的种类、键和字段：

- 键：重复键；不属于本包命名空间的键；
- 引用：未知的物品、设施、科技、武器；
- 数量：非正数或非有限的数量；
- 科技：循环依赖；
- 配方：首尾相连、能凭空增殖的配方环；
- 能力冲突：机库容量或起降速率为 0；带弹药武器却没有弹药舱；带能量武器却没有动力；有发热武器却没有散热；飞行器既无续航也无动力；耗油却没有油箱；有乘员却不带口粮；
- 版本与资源：不支持的 schemaVersion；缺失的美术资源。

真正的新机制（例如新的作战层）仍需要写 Swift 代码。

## 6. 基准（Linux x86_64 发布构建，同一台机器交替运行改造前后各两次）

| 场景 | 改造前（5963b19） | 改造后 | 原因 |
|---|---|---|---|
| 100 国 / 111 万人，每游戏日 | 27–30 ms | 32–35 ms | 食物、设施定义改为经共享注册表的计算属性读取，比静态常量多一层间接；约慢 10–20% |
| 400 台装备同场，每游戏小时 | 9–11 ms | 3.0 ms | 每小时先建一次目标表，不再为每件武器逐个查询兵种 |
| 3 种模式的原有测试（含约 120 人的小世界） | 通过 | 通过 | Society 的模拟代码只改了制作取料一处 |

真机未测：帧率、发热、内存与 GPU 时间都待真机验证。

## 7. 没有做到的（如实列出）

- **开放世界和指挥模式的内容表还没进注册表。** 开放世界的 `parts`（建筑构件）、`weapons`、`armor` 和文明层的同名物品含义不同；直接合并会让旧存档里的同名物品指向错误的定义。需要先给城镇物品改用新键并写存档迁移，本轮没有做。指挥模式的 `SkKind` 仍按数组位置存储。
- **三种模式只共用了库存事务、伤害计算和存档组件。** 生产任务（指挥模式的生产线、都市的建造）、移动和探测仍是各模式自己的实现。
- **世界战役（从世界借出部队进入指挥模式、结算一次）没有做**；都市城市也没有接入国家人口。两个模式仍与世界隔离，因此不会刷出资源，但也没有互通。
- **没有统一的 `RenderSnapshot` 类型。** 2D 与 3D 已经读取同一个 Society 和同一份拾取结果，但不是同一个不可变快照对象。
- **数量单位仍是 `Double`。** 确定性靠固定顺序累加和每城固定随机流保证（有测试），没有改用定点数；跨平台逐位一致没有测试。
- **事件**：文明层的新闻和战斗记录各有上限（400 / 300 条），另有按种类的累计计数；还没有统一的事件编号与因果链。
