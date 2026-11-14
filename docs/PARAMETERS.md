# 参数表

由 `tools/gen_params.py` 从源码生成，数值以源码为准。
三国、战争、城市、生产、事件、玩家和技术上限的参数集中在 `ios/Sources/MoonPixelCore/Realm.swift` 的 `RealmConfig`，随存档保存。
时间单位：年 = 游戏内 1200 秒（1× 速度下 20 分钟）；小时 = 50 秒。


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

## campaigns

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `rationStart` | 8.0 |  |
| `ration` | 0.02 |  |
| `convoyEvery` | 80.0 |  |
| `convoyCarry` | 14.0 |  |
| `moraleStart` | 0.8 |  |
| `moraleLoss` | 1.4 |  |
| `moraleHunger` | 0.2 |  |
| `moraleRally` | 0.1 |  |
| `moraleLeader` | 0.2 |  |
| `waver` | 0.4 |  |
| `rout` | 0.2 |  |
| `routLoss` | 0.1 |  |
| `wallHP` | 60.0 |  |
| `wallMin` | 12 |  |
| `engineHit` | 1.2 |  |
| `ladderHit` | 0.04 |  |
| `occupyTime` | 30.0 |  |
| `meetRange` | 140.0 |  |
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
| `arsenalScale` | 3.0 | weapons research: speed, and the spur of war |
| `arsenalWar` | 1.5 | weapons research: speed, and the spur of war |
| `arsenalPower` | 0.03 | army strength per tier learned, and its ceiling |
| `arsenalPowerCap` | 1.5 | army strength per tier learned, and its ceiling |
| `researchScale` | 1.5 |  |
| `catchUp` | 1.5 |  |
| `breakthroughBoost` | 3.0 |  |

## weather, leisure

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `rainFood` | 0.6 |  |
| `heatSpoil` | 0.01 |  |
| `lightningChance` | 0.5 |  |
| `lightningDamage` | 0.15 |  |
| `festivalFood` | 8.0 |  |
| `festivalEvery` | 1.0 |  |
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

## cities and capitals

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `cityBeds` | 4 |  |
| `cityMinGap` | 40 |  |
| `capitalPop` | 12 |  |
| `cityFood` | 20.0 |  |
| `capitalFoodPerHead` | 4.0 |  |
| `settleEvery` | 0.25 |  |
| `settleBatch` | 8 |  |
| `capitalMoveYears` | 0.3 |  |
| `capitalMoveCooldown` | 5.0 |  |
| `capitalMoveRatio` | 1.6 |  |
| `capitalMoveWood` | 30.0 |  |
| `capitalMoveFood` | 40.0 |  |
| `capitalLostFatigue` | 0.25 |  |
| `govNoCapital` | 0.6 |  |
| `govMoving` | 0.7 |  |
| `govSiege` | 0.8 |  |
| `govNoPalace` | 0.95 |  |
| `millFood` | 0.4 |  |
| `marketFlow` | 0.03 |  |
| `granaryFood` | 150.0 |  |
| `fortFortress` | 0.25 |  |
| `fortTower` | 0.05 |  |
| `fortBallista` | 0.08 |  |
| `fortWall` | 0.3 |  |
| `maxNews` | 120 |  |
| `maxHistory` | 300 |  |

## production

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `cityRadius` | 30 | tiles around the square that count as the town |
| `storeBase` | 80.0 |  |
| `storePerChest` | 60.0 |  |
| `artisansPer` | 5 | adults per station crew |
| `mineIron` | 0.6 |  |
| `mineMoon` | 0.05 |  |
| `toolBonus` | 0.25 |  |
| `toolWear` | 0.01 |  |
| `gearWeapons` | 0.25 |  |
| `gearArmor` | 0.2 |  |
| `playerCraftSpeed` | 0.25 |  |
| `maxNetwork` | 256 | tiles one switch network may span |
| `maxGraves` | 24 |  |
| `maxLog` | 60 |  |
| `maxRuinsPerTown` | 40 |  |
| `maxEffects` | 120 |  |

## 随机事件

概率仅在条件成立时按年计算，全部使用存档内的随机种子。

| 事件 | 每年概率 | 持续（年） | 冷却（年） | 触发条件 | 影响范围 |
| --- | --- | --- | --- | --- | --- |
| `harvest_good` | 0.5 | 0.5 | 1.5 | 本国至少有 1 座建成的农田，且没有歉收 | 该国全部城镇：每座农田每小时额外产粮 |
| `harvest_bad` | 0.35 | 0.5 | 2.0 | 本国至少有 1 座建成的农田，且没有丰收 | 该国全部城镇：存粮每小时损失 2% |
| `general` | 0.4 | 1.0 | 3.0 | 本国士兵不少于 5 人 | 该国全部军团战力 ×1.25 |
| `leader_died` | 0.25 | 0.5 | 1.0 | 领袖年满 55 岁（其他原因死亡也会触发继位） | 该国换领袖；统一时代计入继承争议 |
| `breakthrough` | 0.3 | 0.3 | 2.0 | 尚有未掌握的科技，且有学校/实验室或科技不足 2 项 | 该国研究速度 ×3 |
| `town_defect` | 1.0 | 0 | 1.0 | 城镇不满值达到 1，且多数居民认同另一国 | 单个城镇改旗易帜 |
| `alliance_broken` | 0.6 | 0 | 1.5 | 联盟所针对的强国国力份额已低于 dominanceRelease | 两个结盟国家的关系 |

## 生产配方

| 配方 | 设施 | 投入 | 产出 | 耗时（小时） |
| --- | --- | --- | --- | --- |
| 锯木板 | workbench | (wood, 2) | (planks, 2) | 1 |
| 冶炼铁锭 | furnace | (iron_ore, 2), (wood, 1) | (iron, 1) | 2 |
| 冶炼月钢 | furnace | (moon_ore, 2), (iron, 1), (wood, 2) | (moonsteel, 1) | 4 |
| 烹制口粮 | kitchen | (food, 4), (wood, 1) | (meal, 4) | 1 |
| 建筑构件 | workbench | (planks, 2), (stone, 2) | (parts, 2) | 2 |
| 工具 | workbench | (planks, 1), (iron, 1) | (tools, 1) | 2 |
| 武器 | anvil | (iron, 2), (planks, 1) | (weapons, 1) | 3 |
| 防具 | anvil | (iron, 3) | (armor, 1) | 3 |
| 月钢兵器 | anvil | (moonsteel, 1), (iron, 1) | (weapons, 3) | 4 |
| 攻城器械 | workbench | (planks, 4), (iron, 2), (parts, 2) | (engines, 1) | 6 |

## 建造部件

| 部件 | 地块 | 材料（每格） |
| --- | --- | --- |
| 木地板 | `wood_floor` | (wood, 1) |
| 石地板 | `stone_floor` | (stone, 1) |
| 木墙 | `wall_wood` | (wood, 2) |
| 石墙 | `wall_stone` | (stone, 2) |
| 城门 | `gate` | (wood, 3), (iron, 1) |
| 木门 | `door_wood` | (wood, 2) |
| 围栏 | `fence` | (wood, 1) |
| 床 | `bed` | (wood, 3) |
| 火把 | `torch` | (wood, 1) |
| 道路 | `cobble_road` | (stone, 1) |
| 桥梁 | `bridge_wood` | (wood, 3) |
| 矿井阶梯 | `stairs_down` | (wood, 4), (stone, 4) |
| 工作台 | `workbench` | (wood, 6) |
| 熔炉 | `furnace` | (stone, 8) |
| 铁砧 | `anvil` | (iron, 3) |
| 厨房 | `kitchen` | (stone, 4), (wood, 2) |
| 仓库 | `chest` | (wood, 6) |
| 拉杆 | `lever_off` | (wood, 1), (iron, 1) |
| 压力板 | `plate` | (stone, 1), (iron, 1) |
| 连接线 | `wire` | (iron, 0.25) |
| 灯 | `lamp_off` | (iron, 1) |
| 铁门 | `door_iron` | (iron, 3) |
| 尖刺陷阱 | `trap` | (iron, 2) |
| 瞭望塔 | `tower` | (stone, 12), (parts, 2) |
| 弩炮 | `ballista` | (engines, 1) |
| 王座 | `throne` | (parts, 6), (gold_ore, 2) |
| 旗帜 | `banner_1` | (wood, 2) |
| 市场摊位 | `market_stall` | (wood, 5), (parts, 1) |
| 风车 | `mill` | (wood, 8), (parts, 2) |

## 世界法则与容量策略

`LawOptions`（`Laws.swift`）：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `ratio` | 0.3 | 湮灭：每类内容删除的比例 |
| `spaceTarget` | 0 | 湮灭：大于 0 时改为按要回收的字节数删除 |
| `wResidents` `wBuildings` `wProps` `wChunks` `wHistory` | 各 1.0 | 湮灭：居民、建筑、摆件、区块修改、历史的权重，0 表示不碰 |
| `newSeed` | true | 创世纪：使用新种子，false 为沿用原种子 |
| `radius` | 2 | 归墟：区域为 (2r+1)×(2r+1) 个区块，地上地下一并恢复 |
| `thanosHold` | 1.0 | 灭霸后暂停人口保底补充的年数 |

`StoragePolicy`：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `mode` | cacheFirst | 缓存优先（不删除）/ 自动湮灭 / 区域轮回 |
| `high` / `low` | 0.85 / 0.70 | 超过上限的 85% 开始自动执行，目标降到 70% |
| `cooldown` | 300 | 两次自动执行之间的现实秒数 |
