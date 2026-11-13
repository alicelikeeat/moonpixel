# 迁移说明

## 技术路线

Godot 工程已完全移除，仓库只剩 Swift 一套技术栈。

| 已删除 | 说明 |
| --- | --- |
| `project.godot`、`export_presets.cfg`、`icon.svg*` | Godot 工程与导出配置 |
| `game/`、`tests/` | 全部 GDScript 脚本与 Godot 测试 |
| `tools/*.gd`、`tools/gd.sh` | Godot 专用工具 |
| `.github/workflows/ci.yml` | Godot 的 Linux 测试流程 |
| `content/` 下的 enemies、items、npcs、quests、recipes、skills、structures | 只有 Godot 版本使用的数据 |
| 旧 `docs/` | 描述 Godot 架构的文档 |

保留的通用数据：`content/tiles/tiles.json` 和 `content/biomes/biomes.json`，由 `tools/gen_swift_content.py` 生成
`ios/Sources/MoonPixelCore/ContentData.swift`。修改 JSON 后重新运行该脚本。

CI 只剩 `.github/workflows/ios.yml`：核心测试 → 真机编译 → 未签名 ipa → Release → 模拟器截图与界面测试。

## 存档兼容

旧存档可以直接打开，新增字段全部是可选的：

- 没有三国数据的存档：打开时按地理位置把现有城镇分给三个国家，居民获得所在城镇的国家认同。
  城镇少于三个时，没有领土的国家处于流亡状态，之后由现有居民迁出建城复国，不会凭空增加人口。
- 旧存档的全局科技等级成为三个国家共同的起点。
- 事件日志现在随存档保存（以前不保存）。
- 存档读取失败时，原文件另存为 `index.corrupt-<时间>.json`，不会被新存档覆盖。
- 世界法则执行期间目录里有 `law-journal.json`（只含删除计划，不含被删数据），提交成功后删除；
  打开世界时如果它还在，会先把这次法则执行完。

存档目录结构不变：`Documents/worlds/<id>/`，内含 `index.json`、`meta.json`、`chunks/`、`assets/`。

## 行为变化

- 科技从全局改为按国家研究；界面显示最先进国家的水平。统一时代三国共享已掌握的科技。
- 一句话创建世界时村庄数最少为 3（三国各需要一座城）。
- 武器不再只有视觉效果：命中、伤害、冷却和死亡由核心逻辑结算。新增斧和镐，可采集资源、拆毁道路桥梁和补给站。
- 城镇标签和地图上的城镇点按国家着色；士兵头顶有国家颜色的小旗。
- 存储上限可在世界法则面板里设为 50 MB / 500 MB / 1 GB / 5 GB（默认 5 GB）。

## 1.1 起的变化

- 版本号由 CI 自动递增：每次发布依次为 1.1、1.2、1.3……，Release 标签为 `v1.N`，安装包名为 `MoonPixel-1.N-unsigned.ipa`。
- 新增的存档字段（国家掌握的能力、科技树、天气、动物、玩家的专注/神器/伴侣/花、村民的娱乐需求和恋爱对象）全部可选，旧存档可直接打开；科技树在第一次需要时按世界种子生成。
- 世界生成新增迷宫：每 6×6 区块中有一个区块可能是迷宫。已保存（被修改过）的区块不受影响；旧世界里尚未修改的区块重新载入时可能出现迷宫。
- 村民不再一见钟情：互有好感后先相恋约十分之一年再结为伴侣。
