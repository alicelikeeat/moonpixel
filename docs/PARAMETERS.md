# 参数表

所有三国、战争、事件、玩家和技术上限参数集中在 `ios/Sources/MoonPixelCore/Realm.swift` 的 `RealmConfig`，随存档保存。
时间单位：年 = 游戏内 1200 秒（1× 速度下 20 分钟）。本表由源码生成，数值以源码为准。


## population pressure (weights sum to 1)

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `wFood` | 0.35 |  |
| `wHousing` | 0.25 |  |
| `wJobs` | 0.20 |  |
| `wLand` | 0.20 |  |
| `foodPerHead` | 6.0 | stock per resident that counts as "enough" |
| `landPerTown` | 36.0 | residents one town's land carries comfortably |
| `expansionPressure` | 0.45 | above this, towns send settlers out earlier |
| `softPerTown` | 24.0 | residents per town: crowding starts / hard cap |
| `hardPerTown` | 32.0 | residents per town: crowding starts / hard cap |
| `hardPopHold` | 0.5 | years above the hard cap before a war cycle is forced |

## war and peace (years)

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `warPressure` | 0.15 | pressure needed before a nation considers war |
| `warPressureFull` | 0.6 | pressure at which the yearly chance below applies in full |
| `warChance` | 0.8 | per year at full pressure |
| `minWar` | 0.5 |  |
| `minTruce` | 1.0 |  |
| `peaceCooldown` | 0.5 |  |
| `fatigueDeclareMax` | 0.35 | too tired to start a war above this |
| `fatigueSoft` | 0.7 | truce once the minimum war time has passed |
| `fatigueHard` | 1.0 | truce immediately |
| `intensityHard` | 0.12 | recent battle deaths / world population: truce everywhere |
| `intensityHalfLife` | 0.4 |  |
| `fatigueDeath` | 2.0 | per battle death, divided by the nation's population |
| `fatigueWarYear` | 0.25 |  |
| `fatigueHunger` | 0.5 |  |
| `fatigueDamage` | 0.04 |  |
| `fatigueLostTown` | 0.2 |  |
| `fatigueRecovery` | 0.5 | per year while not at war |

## armies

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `conscriptBase` | 0.12 |  |
| `conscriptPressure` | 0.15 |  |
| `conscriptWar` | 0.22 |  |
| `conscriptUnified` | 0.05 |  |
| `soldierHP` | 140.0 |  |
| `civilianHP` | 100.0 |  |
| `step` | 2.0 | seconds between army updates (same near and far) |
| `marchSpeed` | 34.0 | pixels per second at full supply |
| `lethality` | 0.012 | losses per second per point of enemy power |
| `fortify` | 1.25 | defenders' advantage |
| `techPower` | 0.08 | per technology |
| `minAttack` | 3 |  |
| `attackShare` | 0.65 | share of a garrison that marches |
| `retreatShare` | 0.25 | attackers fall back below this share of their starting strength |
| `fieldUpkeep` | 0.012 | food per soldier per second in the field |
| `starveLoss` | 0.004 | soldiers lost per soldier-second without food |
| `supplyInterval` | 30.0 |  |
| `supplyDistance` | 400.0 | tiles at which distance alone halves supply |
| `supplyRoad` | 0.25 |  |
| `supplyWater` | 0.06 |  |
| `supplyDepot` | 0.15 |  |
| `supplyMin` | 0.15 |  |
| `supplyMax` | 1.2 |  |
| `depotRange` | 12 |  |
| `captureDamage` | 2 |  |
| `refugeeShare` | 0.2 |  |
| `refugeeIntegrate` | 1.0 |  |

## balance of power

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `dominance` | 0.5 |  |
| `dominanceRelease` | 0.42 |  |
| `pactWar` | 2.0 | allies declare on the strong nation this much more readily |
| `ambition` | 0.5 | yearly chance that a dominant nation presses on, whatever its pressure |
| `governFood` | 0.6 | food per occupied resident per year |
| `strongUnrest` | 1.5 |  |
| `strongSupply` | 0.85 |  |
| `submitFatigue` | 0.6 |  |
| `submitShare` | 0.15 |  |

## unrest, exile, unification

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `unrestRate` | 0.35 | per year at full identity mismatch |
| `unrestGarrison` | 2.0 | soldiers per resident that cancel unrest |
| `exileMax` | 2.0 |  |
| `restartDelay` | 0.25 | years an empty world stays empty before settlers return |
| `unityMin` | 1.5 |  |
| `unityMax` | 5.0 |  |
| `fractureBase` | 0.15 |  |
| `fractureIdentity` | 0.6 |  |
| `fractureSuccession` | 0.3 |  |
| `fractureIndependence` | 0.25 |  |
| `unityResearch` | 1.3 |  |
| `unityTrade` | 0.05 |  |
| `splitIdentity` | 1.0 |  |
| `splitGeography` | 0.6 |  |
| `splitMilitary` | 0.4 |  |

## research

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `researchScale` | 1.5 |  |
| `catchUp` | 1.5 |  |
| `breakthroughBoost` | 3.0 |  |

## events

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `harvestBonus` | 1.5 |  |
| `harvestLoss` | 0.02 |  |
| `generalPower` | 1.25 |  |

## player

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `playerHP` | 100.0 |  |
| `playerRegen` | 2.0 |  |
| `soldierHit` | 9.0 |  |
| `hostileRep` | -0.5 |  |
| `roadCost` | 1.0 |  |
| `bridgeCost` | 3.0 |  |
| `depotWood` | 8.0 |  |
| `depotStone` | 4.0 |  |

## technical limits (never left to the war system)

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `maxGraves` | 24 |  |
| `maxLog` | 60 |  |
| `maxRuinsPerTown` | 40 |  |
| `maxEffects` | 120 |  |

## 随机事件

触发条件见 `Society.events`；概率仅在条件成立时按年计算，全部使用存档内的随机种子。

| 事件 | 每年概率 | 持续（年） | 冷却（年） | 触发条件 | 影响范围 |
| --- | --- | --- | --- | --- | --- |
| `harvest_good` | 0.5 | 0.5 | 1.5 | 本国至少有 1 座建成的农田，且没有歉收 | 该国全部城镇：每座农田每小时额外产粮 |
| `harvest_bad` | 0.35 | 0.5 | 2.0 | 本国至少有 1 座建成的农田，且没有丰收 | 该国全部城镇：存粮每小时损失 2% |
| `general` | 0.4 | 1.0 | 3.0 | 本国士兵不少于 5 人 | 该国全部军团战力 ×1.25 |
| `leader_died` | 0.25 | 0.5 | 1.0 | 领袖年满 55 岁（其他原因死亡也会触发继位） | 该国换领袖；统一时代计入继承争议 |
| `breakthrough` | 0.3 | 0.3 | 2.0 | 尚有未掌握的科技，且有学校/实验室或科技不足 2 项 | 该国研究速度 ×3 |
| `town_defect` | 1.0 | 0 | 1.0 | 城镇不满值达到 1，且多数居民认同另一国 | 单个城镇改旗易帜 |
| `alliance_broken` | 0.6 | 0 | 1.5 | 联盟所针对的强国国力份额已低于 dominanceRelease | 两个结盟国家的关系 |

## 世界法则与容量策略

`LawOptions`（`Laws.swift`）：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `ratio` | 0.3 | 湮灭：每类内容删除的比例 |
| `spaceTarget` | 0 | 湮灭：大于 0 时改为按要回收的字节数删除 |
| `wResidents` `wBuildings` `wProps` `wChunks` `wHistory` | 各 1.0 | 湮灭：居民、建筑、摆件、区块修改、历史的权重，0 表示不碰 |
| `newSeed` | true | 创世纪：使用新种子，false 为沿用原种子 |
| `radius` | 2 | 归墟：区域为 (2r+1)×(2r+1) 个区块 |
| `thanosHold` | 1.0 | 灭霸后暂停人口保底补充的年数 |

`StoragePolicy`：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `mode` | cacheFirst | 缓存优先（不删除）/ 自动湮灭 / 区域轮回 |
| `high` / `low` | 0.85 / 0.70 | 超过上限的 85% 开始自动执行，目标降到 70% |
| `cooldown` | 300 | 两次自动执行之间的现实秒数 |

## 武器

| 武器 | 伤害 | 距离（像素） | 冷却（秒） | 类型 |
| --- | --- | --- | --- | --- |
| 空手 | 12 | 20 | 0.45 | 近战弧形 |
| sword | 48 | 30 | 0.5 | 近战弧形 |
| axe | 36 | 26 | 0.6 | 近战弧形 |
| pick | 30 | 26 | 0.6 | 近战弧形 |
| bow | 34 | 170 | 0.8 | 箭矢 |
| staff | 42 | 110 | 1.1 | 范围爆裂 |

平民生命 100，士兵生命 140，玩家生命 100。
