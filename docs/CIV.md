# 无限国度：人口、粮食、科技与军工（文明层）

代码：`ios/Sources/MoonPixelCore/Civ.swift`（地区、人口、粮食、行程、账本）、`CivPolity.swift`（国家、外交、科研、决策）、`CivWar.swift`（工业、装备、部队、作战、舰载航空）、`CivData.swift`（全部参数表）、`CivBridge.swift`（与开放世界的衔接）。界面：`ios/App/CivPanel.swift`。测试：`CivTests`、`CivBridgeTests`、`CivStressTests`。

## 分层

| 层 | 内容 | 频率 |
|---|---|---|
| 详细层 | 玩家附近的城镇（Society 的每个居民、军团、建筑） | 原有逻辑 |
| 区域层 | 已发现地区的城市：人口群体（整数、按年龄段与饥饿状态）、粮食与物资、设施、行程、部队 | 每游戏小时（作战）/每游戏日（生产、吃饭、出生死亡） |
| 宏观层 | 国家：外交（稀疏关系）、科研、财政、决策、统一与分裂 | 每游戏日 |
| 未发现地区 | 不模拟、不计入人口；由世界种子 + 地区坐标 + 规则版本确定，首次发现时生成一次 | — |

详细层城镇在区域层是 `detail` 城市：人口和粮食直接从居民和城镇库存读出，**不重复模拟、不重复计数**。两层共用一个国家编号计数器，编号永不复用。地区由玩家实际行走的位置（`Society.explorer`）和城镇周边发现，**镜头位置不会发现土地**。

时间：区域层每 `Society.hour`（50 秒游戏时间）走一步；一天 = 24 步 = `MP.daySeconds`；一年 = `daysPerYear` 天（默认 8）。按游戏时钟推进，倍速、镜头、3D 都不改变结果（`testTheSameDaysGiveTheSameWorldAtAnySpeedAndAcrossASave`）。

## 人口账本

每座城的人口是 3 个年龄段 × 6 个饥饿状态的整数表（饱足、轻度饥饿、明显饥饿、严重饥饿、饥荒衰弱、濒死）。所有变化只有以下几种，每一种都记入城市当日账、累计账和全局账：

```
期末人口 = 期初人口 + 出生 − 死亡(按原因) + 迁入 − 迁出 − 入伍 + 退伍
全局：城市人口 + 行程中的人 + 部队人员 = 新纳入统计 + 出生 − 死亡
```

- **新纳入统计**：首次发现的城邦里本来就有的人，单列，不算出生。
- **入伍/退伍**：从城市成年人转到部队（仍是本国人口），退役回到城市；阵亡只在 `destroyed` 里扣一次。
- **迁移/难民/殖民**：先从原城扣出，变成路上的 `CivTrip`（自带口粮，途中会饿、会死，原因记为 journey），到达后加入目的地；目的地消失则返回或就近安顿，不会无声消失。
- **易主、统一、分裂、联邦**只改变城市的控制者，不改变人数，居民的认同（`culture`）慢慢变化。
- 每天 `audit()` 检查总数、负数、悬空引用和重复编号；测试在每一天都调用。

## 粮食账本

```
现存（城市 + 行程 + 部队） = 首次发现时已有 + 生产 − 食用 − 腐坏 − 丢失（截获/损毁/运输损耗） − 作为原料消耗
```

转移是“先取后放”：装车时从仓库扣除并归属行程，到达时才入库；车队被截获时记为丢失。粮食只能从**能到达的**库存中吃：被围城市的外援在包围圈外等待（3 天后被截获），国家其他地方有粮也帮不上。

| 食物 | 营养（成人日） | 保质（天） | 需要科技 |
|---|---|---|---|
| 谷物 `grain` | 1.0 | 360 | — |
| 蔬菜 `vegetable` | 0.5 | 12 | — |
| 肉 `meat` | 1.2 | 6 | — |
| 奶 `milk` | 0.6 | 3 | — |
| 鱼 `fish` | 1.0 | 4 | — |
| 面包 `bread` | 1.25 | 8 | — |
| 熟食 `meal` | 1.5 | 2 | — |
| 便携口粮 `ration` | 2.0 | 500 | preserving |
| 温室蔬菜 `hydro` | 0.6 | 14 | greenhouse |
| 合成营养 `synth` | 2.5 | 900 | synth_food |

吃的顺序：先吃最易坏的。粮仓让谷物、面包、口粮腐坏减半；冷链让易腐食物腐坏降到 40%。

## 饥饿参数（游戏平衡值，不是医学结论）

| 参数 | 默认 | 说明 |
|---|---|---|
| 每日需要 | 儿童 0.6、成人 1.0、老人 0.8 | 成人日营养；劳作 +0.2×0.6，士兵 +0.3 |
| 恢复门槛 `fedAbove` | 0.95 | 当天供应 ≥95% 才向好的方向走一步 |
| 恶化门槛 `hungryBelow` | 0.8 | 低于 80% 才向坏的方向走；0.8–0.95 之间保持不变（滞回） |
| 恶化速度 | 每天 (1−供应)×0.5 的人下降一级 | 完全断粮约 10 天到濒死 |
| 恢复速度 | 每天 50% 的人上升一级 | 吃饱后逐级恢复，不会立刻全好 |
| 饥饿死亡 | 衰弱 2%/天、濒死 12%/天 | 只发生在最后两级 |
| 劳作效率 | 1, 0.97, 0.85, 0.6, 0.35, 0.15 | 饥饿的人还能觅食（每人 0.25 营养/天），避免全员停工的死循环 |
| 生育 | 1, 1, 0.8, 0.4, 0.1, 0 | |
| 外迁 | 0, 0, 1%, 5%, 8%, 5% /天 | 外加拥挤造成的外迁 |
| 紧急限量 | 85% | 落在滞回区内：大家略饿但不再恶化，存粮更持久 |

配给政策：正常、紧急限量、儿童优先、军需优先；政策下达后一天生效，避免来回振荡。

## 人口参数

儿童 4 年成年、成年 10 年后进入老年；自然死亡率 儿童 1.2%/年、成人 0.6%/年、老人 20%/年，诊所最多减少 45%。生育 0.5 /对/年，除以 (1 + 0.25×富裕度)，拥挤时除以拥挤度²，缺水按比例减少。住房 6 人/栋（另有 18 人的临时住所），水井 40 人，靠河或海 400 人。

## 国家

- **诞生**：城邦（发现时生成）、殖民（拥挤城市派出 32 人与 25 天口粮，到达后建城）、叛乱（不满 ≥1 的相邻城市成组独立）、复国（叛乱城市多数仍认同已亡国家时恢复该国）、玩家建国（`foundNation`，人从现有城市迁出）、文明重启（每个新村落一个新国家）。
- **扩张**：征服（敌军占据城区且无守军 12 小时）、归附（一城小国、厌战、对手强 3 倍）、联邦（同盟 ≥3 年且好感 ≥0.85）。
- **分裂**：统一王朝按每座城的认同和驻军归属分成**实际存在的派别数**；只剩一个派别就不分裂，不再有定时分裂。区域层叛乱同理。
- **消亡**：失去所有城市进入流亡；流亡超过 6 年且认同人口 <30 成为历史实体，ID、名称、纪事保留。
- **外交**：只为相邻（2 区内）、贸易、交战、同盟或有领土争议的国家建立关系；长期无往来的中性关系会被移除。
- **区分**：颜色按黄金角分布，另有 8 种纹章形状和两字简称。

## 科技（39 项，6 个时代标签）

时代只是说明；能否研究看前置科技、研究设施、研究人员（学校/研究院/实验室和受饥饿影响的成人）。贸易或和平邻国已掌握的科技研究成本 −40%；缴获装备给予部分进度（每次 30%，上限 60%），不直接获得完整制造能力。分裂出的新国只继承其城市自身能支撑的知识。

| 科技 | 分支 | 时代标签 | 前置 | 研究点 | 研究设施 |
|---|---|---|---|---|---|
| 农耕 `farming` | agri | 农耕手工 | — | 0 | 无 |
| 畜牧 `husbandry` | agri | 农耕手工 | farming | 20 | 无 |
| 渔船 `fishing` | naval | 农耕手工 | farming | 20 | 无 |
| 灌溉 `irrigation` | agri | 农耕手工 | farming | 40 | 无 |
| 文字与学堂 `writing` | info | 农耕手工 | — | 30 | 无 |
| 冶金 `metallurgy` | industry | 冶金机械 | writing | 60 | 学校 |
| 食物保存 `preserving` | agri | 冶金机械 | husbandry | 50 | 学校 |
| 机械加工 `machining` | industry | 冶金机械 | metallurgy | 90 | 学校 |
| 轮作 `rotation` | agri | 冶金机械 | irrigation | 70 | 学校 |
| 医学 `medicine` | info | 冶金机械 | writing | 80 | 学校 |
| 蒸汽动力 `steam` | industry | 工业 | machining | 140 | 研究院 |
| 钢铁 `steel` | industry | 工业 | machining | 150 | 研究院 |
| 步枪 `rifles` | land | 工业 | steel | 120 | 研究院 |
| 化肥 `fertilizer` | agri | 工业 | rotation, steam | 160 | 研究院 |
| 铁路 `railways` | industry | 工业 | steam, steel | 180 | 研究院 |
| 造船工程 `naval_eng` | naval | 工业 | steel, fishing | 180 | 研究院 |
| 电力 `electricity` | industry | 电气化 | steam | 260 | 研究院 |
| 石油炼化 `oil` | industry | 电气化 | steam | 240 | 研究院 |
| 内燃机 `engines` | land | 电气化 | oil, machining | 260 | 研究院 |
| 现代火炮 `artillery` | land | 电气化 | rifles, engines | 260 | 研究院 |
| 冷链 `cold_chain` | agri | 电气化 | electricity, preserving | 220 | 研究院 |
| 动力飞行 `flight` | air | 电气化 | engines | 320 | 实验室 |
| 无线电与雷达 `radio` | info | 电气化 | electricity | 300 | 实验室 |
| 深水船坞 `deep_yard` | naval | 电气化 | naval_eng, electricity | 360 | 实验室 |
| 电子学 `electronics` | info | 信息化 | radio | 420 | 实验室 |
| 温室水培 `greenhouse` | agri | 信息化 | fertilizer, electricity | 380 | 实验室 |
| 制导导弹 `missiles` | land | 信息化 | artillery, electronics | 480 | 实验室 |
| 喷气式飞机 `jets` | air | 信息化 | flight, electronics | 500 | 实验室 |
| 舰载航空 `carrier_ops` | naval | 信息化 | deep_yard, jets | 560 | 实验室 |
| 无人机 `drones` | air | 信息化 | electronics, flight | 440 | 实验室 |
| 计算机 `computing` | info | 信息化 | electronics | 520 | 实验室 |
| 机器人学 `robotics` | industry | 信息化 | computing, engines | 600 | 实验室 |
| 自动农场 `auto_farm` | agri | 未来科技 | robotics, greenhouse | 700 | 实验室 |
| 重型人形机体 `frame` | mecha | 未来科技 | robotics, missiles | 820 | 实验室 |
| 紧凑聚变 `fusion` | industry | 未来科技 | computing, electricity | 900 | 实验室 |
| 机体反应堆 `frame_reactor` | mecha | 未来科技 | frame, fusion | 900 | 实验室 |
| 合成营养 `synth_food` | agri | 未来科技 | auto_farm, fusion | 860 | 实验室 |
| 空天船体 `aerospace` | space | 未来科技 | jets, fusion | 1000 | 实验室 |
| 场升力 `lift` | space | 未来科技 | aerospace, frame_reactor | 1200 | 实验室 |

## 工业链

原料（木、石、铁矿、煤、原油）→ 钢材、燃料 → 机械部件、电子元件 → 装甲板、发动机、武器系统、反应堆芯 → 整机与舰船。每个配方有输入、输出、设施、工时、能源；设施按工人和电力开工。装备按阶段从库存中**整段扣料**，缺料暂停并说明原因；取消返还已投入材料的 50%，其余记为损失；所在城市失守时项目取消。

## 装备

原创单位（不使用任何既有作品的名称或机体设计）。完工后停在城市仓库，**未配乘员、空油空弹**；出库时从城市成年人中抽调乘员、从库存加注燃料弹药和口粮。

| 装备 | 层 | 体型 | 科技 | 工厂 | 分段材料 | 每段工时 | 乘员 | 生命/装甲 | 速度(区/天) | 燃料/能量(天) | 弹药/口粮 | 探测/隐蔽 | 武器 | 机库 | 关键部位 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 民兵队 `levy` | ground | person | — | barracks | timber: 10 | 12h | 30 | 120/0 | 1.0 | 0/0·0 | 0/300 | 0/1 | spear | — | — |
| 步兵连 `infantry` | ground | person | rifles | barracks | steel: 2, ammo: 10 | 12h | 20 | 120/0 | 1.0 | 0/0·0 | 30/120 | 0/1 | rifle | — | — |
| 反机甲连 `lancers` | ground | person | missiles | barracks | weapons: 2, ammo: 10 | 16h | 16 | 100/0 | 1.0 | 0/0·0 | 24/100 | 0/1 | antiFrame, rifle | — | — |
| 装甲车队 `armour` | ground | vehicle | engines | motor_works | steel: 10, engine: 2 ／ armor: 4, parts: 4 | 24h | 12 | 220/1 | 2.0 | 40/6·0 | 30/60 | 0/0 | cannon | — | power, weapons |
| 炮兵连 `artillery` | ground | vehicle | artillery | motor_works | steel: 12, parts: 6 ／ engine: 1, ammo: 20 | 24h | 14 | 120/0 | 1.2 | 30/4·0 | 60/70 | 0/0 | howitzer | — | weapons |
| 防空连 `air_defence` | ground | vehicle | missiles, radio | motor_works | steel: 10, electronics: 6 ／ weapons: 3, ammo: 20 | 24h | 12 | 120/0 | 1.2 | 30/3·0 | 40/60 | 2/0 | sam, longSam | — | weapons, control |
| 无人机编队 `drone` | lowAir | person | drones | aircraft_works | electronics: 4, parts: 3 | 12h | 0 | 30/0 | 6 | 0/0·0 | 6/0 | 2/2 | droneShot | 舰载 | — |
| 攻击战斗机 `fighter` | highAir | vehicle | jets | aircraft_works | steel: 8, engine: 2 ／ electronics: 6, weapons: 2 | 24h | 2 | 90/1 | 12 | 20/0·0 | 8/4 | 2/1 | airMissile, strike | 舰载 | — |
| 护卫舰 `escort` | sea | huge | naval_eng, radio | shipyard | steel: 40, engine: 3 ／ armor: 8, weapons: 3, electronics: 4 | 48h | 80 | 500/2 | 3 | 120/10·0 | 60/600 | 2/0 | naval, shipAA, depth | — | power, weapons, control |
| 攻击潜艇 `submarine` | underwater | huge | deep_yard, electronics | deep_yard | steel: 50, engine: 4 ／ electronics: 10, weapons: 4 | 60h | 50 | 360/2 | 2.5 | 160/8·0 | 24/500 | 1/3 | torpedo | — | power, weapons |
| 潮墙级航空母舰 `carrier` | sea | huge | carrier_ops | deep_yard | steel: 200, engine: 8 ／ armor: 30, parts: 40 ／ electronics: 30, weapons: 6 | 96h | 400 | 2200/3 | 2.5 | 600/40·0 | 200/4000 | 3/0 | shipAA | 12·4/h | power, hangar, control, weapons |
| 守望者重型机兵 `frame` | ground | large | frame, frame_reactor | frame_works | steel: 60, armor: 20 ／ parts: 30, engine: 4 ／ electronics: 20, weapons: 4, core: 1 | 72h | 1 | 900/2 | 2.5 | 0/0·30 | 0/30 | 1/0 | beam, blade | — | power, weapons, control, cooling |
| 穹顶级空天母舰 `sky_carrier` | highAir | huge | lift, carrier_ops | sky_yard | steel: 400, armor: 60 ／ parts: 120, engine: 16 ／ electronics: 120, weapons: 10, core: 6 | 160h | 300 | 3200/3 | 4 | 0/0·240 | 0/3000 | 4/0 | skyBattery | 8·2/h | power, cooling, hangar, control, weapons |

| 武器 | 射程(区) | 可打击层 | 伤害 | 对软/装甲/重装/建筑 | 弹药 | 能量 | 冷却(h) | 飞行(h) | 热量 |
|---|---|---|---|---|---|---|---|---|---|
| `spears` | 0 | ground | 2.5 | 1, 0.1, 0.02, 0.05 | 0 | 0 | 1 | 0 | 0 |
| `rifle` | 0 | ground, lowAir | 4 | 1, 0.15, 0.05, 0.1 | 0.2 | 0 | 1 | 0 | 0 |
| `cannon` | 0 | ground, sea | 20 | 0.8, 1, 0.5, 0.8 | 1 | 0 | 1 | 0 | 0 |
| `howitzer` | 1 | ground, sea | 30 | 1, 0.7, 0.4, 1.2 | 2 | 0 | 2 | 1 | 0 |
| `sam` | 1 | lowAir, highAir | 40 | 1, 1, 0.6, 0.3 | 2 | 0 | 2 | 1 | 0 |
| `long_sam` | 2 | highAir, nearSpace | 60 | 1, 1, 0.7, 0.4 | 4 | 0 | 4 | 2 | 0 |
| `drone_strike` | 0 | ground, sea | 12 | 1, 0.6, 0.2, 0.5 | 0.5 | 0 | 3 | 0 | 0 |
| `air_missile` | 1 | lowAir, highAir | 35 | 1, 1, 0.5, 0.2 | 1 | 0 | 2 | 0 | 0 |
| `strike` | 0 | ground, sea | 45 | 1, 1, 0.6, 1.2 | 2 | 0 | 3 | 0 | 0 |
| `torpedo` | 0 | sea, underwater | 80 | 1, 1, 1, 1 | 2 | 0 | 3 | 1 | 0 |
| `depth_charge` | 0 | underwater | 40 | 1, 1, 1, 1 | 1 | 0 | 2 | 0 | 0 |
| `naval_gun` | 1 | sea, ground | 35 | 1, 1, 0.6, 1 | 2 | 0 | 2 | 1 | 0 |
| `ship_aa` | 0 | lowAir, highAir | 22 | 1, 1, 0.5, 0.2 | 1 | 0 | 1 | 0 | 0 |
| `beam_rifle` | 0 | ground, sea, lowAir | 60 | 1, 1, 0.9, 1 | 0 | 6 | 1 | 0 | 30 |
| `heat_blade` | 0 | ground | 90 | 1, 1, 1.2, 1.5 | 0 | 3 | 1 | 0 | 20 |
| `lance_missile` | 0 | ground | 70 | 0.3, 1, 1.4, 0.8 | 2 | 0 | 2 | 0 | 0 |
| `sky_battery` | 1 | ground, sea, lowAir, highAir | 40 | 1, 1, 0.8, 1 | 0 | 20 | 3 | 0 | 40 |

### 规则要点

- **通行**：地区边按地形判断。人员可翻山；车辆需要山地 <60%；重型机兵需要 <35%（无法通过山口）；航母需要两侧深水 ≥30%；空中单位不受地形限制但受燃料/能量限制。
- **层**：地面、水面、水下、低空、高空、近空间。武器只能打击自己列出的层；步枪打不到高空战机，普通防空导弹打不到巡航在近空间的空天母舰（需要远程防空导弹）。
- **探测**：只能攻击当前看得到的目标；过期情报只保留最后位置。潜艇只能被同区有反潜武器的单位发现；近空间目标需要远程雷达。
- **命中**：直射立即结算；炮弹和导弹有飞行时间，落地时目标仍在原地才命中，伤害和命中事件在同一时刻产生。
- **关键部位**：动力（失去后不能移动、能量武器失效）、武器、控制（命中率减半）、冷却（散热减弱）、机库（不能起降）。
- **补给**：部队在己方城市 3 区内且道路未被敌军截断时补给（远处有 30% 损耗）；在外时可就地征粮；缺粮会饥饿、士气下降，人员不足一半时装备无法操作。
- **舰载航空**：舰载机是真实单位，状态有停放、出击、返航；起降受甲板每小时吞吐量限制；燃料只够往返时会返航；母舰被击毁时，停放的飞机随舰损失，在空的飞机改降其他母舰或机场，否则迫降（乘员在己方区域获救，否则死亡）。
- **空天母舰**：能量消耗巨大，需由城市电力充能；能量耗尽会强制降落；在近空间巡航时既看不到大多数目标也无法攻击。

## 存档与迁移

- 文明层保存在 `Realm.civBox`，随世界存档走同一套原子保存事务。`Civ.schemaVersion = 1`；字典按编号排序写成列表；每个字段缺失时取默认值；比当前版本更新的存档会被拒绝而不是被误读。
- 规则参数（`CivConfig`）不写入存档，属于游戏版本。
- **旧存档**：没有 `civBox` 时首次使用自动创建；原三国按原 ID、名称、颜色成为文明层国家（`detailed`），居民、国籍、库存、科技和纪事都不动；周边地区在首次运行时按种子发现。
- 国家编号：新国家从共享计数器取号，保证 > 所有已有编号。

## 性能（Linux x86_64 发布构建，非手机实测）

| 场景 | 结果 |
|---|---|
| 10 国 / 1.1 万人（43 城） | 1.6 ms / 游戏日，存档 10 ms，0.1 MB |
| 50 国 / 11 万人（207 城） | 9.8 ms / 游戏日，存档 39 ms，0.6 MB |
| 100 国 / 111 万人（422 城） | 23 ms / 游戏日，存档 78 ms，1.2 MB |
| 50 / 200 / 400 台装备同场作战（含机兵、航母与舰载机、空天母舰） | 0.24 / 2.3 / 9.1 ms / 游戏小时 |
| 3 个种子 × 400 天长期运行 | 每天审计通过；出现战争、占领、流亡、复国/独立/归附、建城、科研 |

## 已知限制

- 区域层一天的计算集中在日界一次完成：百万人口时约 23 ms，在高倍速下可能造成一帧卡顿（尚未分摊到各小时）。
- 详细层（玩家附近的城镇和军团）与区域层的战争是两套作战：外交关系各自维护，区域部队不会攻打详细层城镇，详细层军团也不会攻打区域城市。
- 指挥模式的独立遭遇战与世界战役尚未打通；都市模式仍是独立城市，未接入国家人口。
- 机兵、航母、空天母舰目前只在文明层有完整规则和面板操作，2D/3D 地图上还没有它们的模型与动画。
- 未在真机上运行 60 分钟测发热、内存和帧时间。
