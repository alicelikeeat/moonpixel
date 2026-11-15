#!/usr/bin/env python3
"""Write docs/PARAMETERS.md from the tunable settings in the Swift sources."""
import os, re
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
core = os.path.join(root, "ios/Sources/MoonPixelCore")
src = open(os.path.join(core, "Realm.swift")).read()
body = src[src.index("public struct RealmConfig"):]
body = body[:body.index("    public init() {}")]
rows, section = [], ""
for line in body.split("\n"):
    line = line.strip()
    m = re.match(r"// --- (.*)", line)
    if m: section = m.group(1); continue
    if not line.startswith("public var") or "events:" in line: continue
    code, _, comment = line.partition("//")
    for part in code.replace("public var", "").split(","):
        if "=" in part:
            n, v = part.split("=")[0].strip(), part.split("=")[1].strip()
            rows.append((section, n, v, comment.strip()))
out = ["# 参数表", "", "由 `tools/gen_params.py` 从源码生成，数值以源码为准。",
       "三国、战争、城市、生产、事件、玩家和技术上限的参数集中在 `ios/Sources/MoonPixelCore/Realm.swift` 的 `RealmConfig`，随存档保存。",
       "时间单位：年 = 游戏内 1200 秒（1× 速度下 20 分钟）；小时 = 50 秒。", ""]
cur = None
for sec, n, v, c in rows:
    if sec != cur:
        out += ["", "## " + sec, "", "| 参数 | 默认值 | 说明 |", "| --- | --- | --- |"]; cur = sec
    out.append("| `%s` | %s | %s |" % (n, v, c))
ev = re.findall(r'"(\w+)": EventRule\(chance: ([\d.]+), duration: ([\d.]+), cooldown: ([\d.]+)\)', src)
cond = {"harvest_good": ("本国至少有 1 座建成的农田，且没有歉收", "该国全部城镇：每座农田每小时额外产粮"),
        "harvest_bad": ("本国至少有 1 座建成的农田，且没有丰收", "该国全部城镇：存粮每小时损失 2%"),
        "general": ("本国士兵不少于 5 人", "该国全部军团战力 ×1.25"),
        "leader_died": ("领袖年满 55 岁（其他原因死亡也会触发继位）", "该国换领袖；统一时代计入继承争议"),
        "breakthrough": ("尚有未掌握的科技，且有学校/实验室或科技不足 2 项", "该国研究速度 ×3"),
        "town_defect": ("城镇不满值达到 1，且多数居民认同另一国", "单个城镇改旗易帜"),
        "alliance_broken": ("联盟所针对的强国国力份额已低于 dominanceRelease", "两个结盟国家的关系")}
out += ["", "## 随机事件", "", "概率仅在条件成立时按年计算，全部使用存档内的随机种子。", "",
        "| 事件 | 每年概率 | 持续（年） | 冷却（年） | 触发条件 | 影响范围 |", "| --- | --- | --- | --- | --- | --- |"]
for k, ch, du, co in ev:
    c = cond.get(k, ("", ""))
    out.append("| `%s` | %s | %s | %s | %s | %s |" % (k, ch, du, co, c[0], c[1]))
eco = open(os.path.join(core, "Economy.swift")).read()
out += ["", "## 生产配方", "", "| 配方 | 设施 | 投入 | 产出 | 耗时（小时） |", "| --- | --- | --- | --- | --- |"]
for m in re.finditer(r'Recipe\(key: "(\w+)", station: "(\w+)", en: "[^"]*", zh: "([^"]*)", inputs: \[([^\]]*)\], outputs: \[([^\]]*)\], hours: ([\d.]+)\)', eco):
    out.append("| %s | %s | %s | %s | %s |" % (m.group(3), m.group(2), m.group(4).replace('"', ""), m.group(5).replace('"', ""), m.group(6)))
bld = open(os.path.join(core, "Build.swift")).read()
out += ["", "## 建造部件", "", "| 部件 | 地块 | 材料（每格） |", "| --- | --- | --- |"]
for m in re.finditer(r'p\("(\w+)", "(\w+)", "[^"]*", "([^"]*)", \d, \[([^\]]*)\], \d', bld):
    out.append("| %s | `%s` | %s |" % (m.group(3), m.group(2), m.group(4).replace('"', "")))
law = ["", "## 世界法则与容量策略", "", "`LawOptions`（`Laws.swift`）：", "", "| 参数 | 默认值 | 说明 |", "| --- | --- | --- |",
       "| `ratio` | 0.3 | 湮灭：每类内容删除的比例 |", "| `spaceTarget` | 0 | 湮灭：大于 0 时改为按要回收的字节数删除 |",
       "| `wResidents` `wBuildings` `wProps` `wChunks` `wHistory` | 各 1.0 | 湮灭：居民、建筑、摆件、区块修改、历史的权重，0 表示不碰 |",
       "| `newSeed` | true | 创世纪：使用新种子，false 为沿用原种子 |", "| `radius` | 2 | 归墟：区域为 (2r+1)×(2r+1) 个区块，地上地下一并恢复 |",
       "| `thanosHold` | 1.0 | 灭霸后暂停人口保底补充的年数 |", "", "`StoragePolicy`：", "", "| 参数 | 默认值 | 说明 |", "| --- | --- | --- |",
       "| `mode` | cacheFirst | 缓存优先（不删除）/ 自动湮灭 / 区域轮回 |", "| `high` / `low` | 0.85 / 0.70 | 超过上限的 85% 开始自动执行，目标降到 70% |",
       "| `cooldown` | 300 | 两次自动执行之间的现实秒数 |"]
out += law
# frame time, drawing budgets and bookkeeping limits (read from the sources so this table cannot drift)
def grab(path, pattern, default="?"):
    m = re.search(pattern, open(os.path.join(root, path)).read())
    return m.group(1) if m else default
fr = "ios/Sources/MoonPixelCore/Frame.swift"; bt = "ios/Sources/MoonPixelCore/Battle.swift"; gs = "ios/App/GameScene.swift"; ct = "ios/Sources/MoonPixelCore/Contrib.swift"; wa = "ios/Sources/MoonPixelCore/War.swift"; so = "ios/Sources/MoonPixelCore/Society.swift"
out += ["", "## 帧时间、绘制预算与记录上限", "", "这些不随存档保存，属于引擎常量。", "", "| 参数 | 值 | 位置 | 说明 |", "| --- | --- | --- | --- |",
        "| `GameScene.simSteps` | %s | `App/GameScene.swift` | 每档速度（暂停、1×、4×、16×、64×）的固定模拟步长（游戏秒）；同一档速度永远是同样的步长 |" % grab(gs, r"static let simSteps: \[Double\] = (\[[^\]]*\])"),
        "| 积压上限 | 步长 × 8 | `App/GameScene.swift` | 超过的游戏时间被丢弃并计入“丢弃”，界面显示实际速度 |",
        "| 每帧模拟时间片 | %s 秒 | `App/GameScene.swift` | 一帧内用于模拟的最长现实时间 |" % grab(gs, r"let budgetEnd = CACurrentMediaTime\(\) \+ ([\d.]+)"),
        "| 城镇规划 / 资源扫描每步上限 | max(2, ⌈dt·城镇数/6·1.5⌉) / max(1, ⌈dt·城镇数/25·1.5⌉) | `Society.tick` | 同时到期的重任务分到后续几步，最久未做的优先；上限高于平均需求 |",
        "| 后台烘焙并发 | %s | `App/GameScene.swift` | 同时在后台生成的区块位图数 |" % grab(gs, r"BakeQueue\(maxInFlight: (\d+)\)"),
        "| 区块纹理缓存 | %s 字节 | `App/GameScene.swift` | 按字节计的 LRU；屏幕上的永不淘汰；内存警告时清到只剩屏幕上的 |" % grab(gs, r"ByteLRU<BakeKey, SKTexture>\(budget: ([^)]+)\)"),
        "| 空间索引格子 | %s 像素 | `Frame.swift` | 屏幕内人物查询只看视野下的格子；每个模拟步最多重建一次 |" % grab(fr, r"static let cell = ([\d.]+)"),
        "| 士兵绘制档位 | %s | `Battle.swift` | 由实测 p95 帧时间选择 |" % grab(bt, r"static let tiers = (\[[^\]]*\])"),
        "| 特效档位 | %s | `Battle.swift` | 先降特效，后降士兵数 |" % grab(bt, r"static let effects = (\[[^\]]*\])"),
        "| 降档 / 升档阈值 | p95 > %s ms 持续 %s 秒 / p95 < %s ms 持续 %s 秒 | `Battle.swift` | 降得快、升得慢，不闪烁 |" % (grab(bt, r"public var slow = ([\d.]+)"), grab(bt, r"public var downAfter = ([\d.]+)"), grab(bt, r"fast = ([\d.]+)"), grab(bt, r"upAfter = ([\d.]+)")),
        "| 细节层级 | 远 < 0.8 ≤ 中 < 1.6 ≤ 近（缩放） | `Battle.swift` | 远：只有军旗与人数；中：士兵身形；近：加马、小旗和交战动作 |",
        "| 阵亡账本保留战斗数 | %s | `Battle.swift` | 总数与各国合计不受此限 |" % grab(bt, r"static let keep = (\d+)"),
        "| 玩家贡献保留条数 | %s | `Contrib.swift` | 去重键全部保留 |" % grab(ct, r"static let keep = (\d+)"),
        "| 行军寻路预算 | %s 次扩展 | `War.swift` | 用尽时返回“部分”路线，不是“不可达” |" % grab(wa, r"budget: Int = ([\d_]+)").replace("_", ""),
        "| 道路代价 / 最小步价 | %s | `War.swift` | 启发函数按最便宜地面计算，保持可采纳 |" % grab(wa, r"static let minStep: Float = ([\d.]+)"),
        ]
open(os.path.join(root, "docs/PARAMETERS.md"), "w").write("\n".join(out) + "\n")
print("%d settings, %d events" % (len(rows), len(ev)))
