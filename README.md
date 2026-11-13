# MoonPixel

iOS 原生的 2D 像素开放世界：自主 NPC 社会、三国轮回、无限地图、离线运行，MIT 开源。
*A native iOS pixel world where three nations of autonomous villagers rise, fight, unite and break apart again.*

技术栈只有一套：**Swift 核心逻辑（`MoonPixelCore`）+ SpriteKit 渲染 + SwiftUI 界面**。iOS 26 使用系统 Liquid Glass，更低版本回退为毛玻璃材质。

## 构建与测试

```bash
cd ios
swift test -c release -Xswiftc -enable-testing     # 核心逻辑测试，Linux / macOS 均可
brew install xcodegen && xcodegen generate          # 生成 Xcode 工程（仅 macOS）
```

每次推送由 GitHub Actions（`.github/workflows/ios.yml`）运行核心测试、编译真机版本、打出**未签名 ipa** 并发布到
[Releases](https://github.com/alicelikeeat/moonpixel/releases)，随后在 iOS 模拟器里启动、截图并运行界面测试，截图附在同一个 Release 下。
未签名 ipa 需要自行签名后才能安装。

## 目录

| 路径 | 内容 |
| --- | --- |
| `ios/Sources/MoonPixelCore` | 纯 Swift 逻辑：世界生成、NPC 社会、三国（`Realm.swift`）、玩家行动（`Player.swift`）、世界法则与容量策略（`Laws.swift`）、像素美术与照片处理 |
| `ios/App` | SpriteKit 场景与 SwiftUI 界面 |
| `ios/Tests`、`ios/UITests` | 核心测试与模拟器界面测试 |
| `content/` + `tools/gen_swift_content.py` | 地块与群系数据（JSON），生成 `ContentData.swift` |
| `docs/` | [迁移说明](docs/MIGRATION.md)、[参数表](docs/PARAMETERS.md)、[测试结果与未验证事项](docs/TESTING.md) |

## 功能

- **自主 NPC 社会**：村民按饥饿、精力、社交和职业自己决定做什么；采集、建造、成家、生育、衰老、死亡；每户一栋房；自动研究科技直到人工智能。
- **三国轮回**：世界始终有三个国家，各有领土、居民、城镇、资源、军队、科技、领袖和国家认同。
  - 人口压力同时看粮食、住房、岗位和土地；压力推高扩张、征兵和宣战概率，超过硬上限并持续一段时间会触发战争周期。
  - 伤亡、缺粮、损毁和战争时长累积疲劳；疲劳或全局烈度到达硬阈值强制休战。开战与休战阈值不同，并有最短持续时间和冷却期。
  - 一国过强时另外两国结盟，强国承担补给、治理和占领区不满的成本。
  - 可以通过占领和归附偶发统一；统一时代有贸易、科技交流收益，也有继承争议和地方独立；到期后按居民认同、地理和驻军重新划分为三个实际拥有领土的国家。
  - 七种随机事件：丰收、歉收、将领崛起、领袖去世、技术突破、城镇倒戈、联盟破裂，均有触发条件、持续时间、冷却和可复现的随机种子。
- **玩家**：默认是自由旅人，可加入或退出任一国家。可以捐赠物资、参战（命中、伤害、冷却、死亡、阵营判定）、修建或拆毁道路、桥梁和补给站、接纳难民，并在三国面板查看疆域、关系、人口、压力和疲劳。
- **世界法则**（全屏玻璃面板，一键执行、永久删除）：灭霸、湮灭、创世纪、归墟。删除计划写入日志后分批执行，中断后下次启动会继续完成。
- **存储**：区分缓存清理与永久删除；三种容量策略（缓存优先、自动湮灭、区域轮回）；按区块、人物、图片、头像、索引、历史统计占用。
- **武器、能量武器、魔法、神术、真言**：41 种能力，从手枪、机枪、导弹、电磁炮到等离子光刃、轨道激光、陨石术、天罚、雷神之锤和真言。每个世界有自己随机生成的科技树，三国沿着各自的路线研究，军队战力随之提高；玩家使用所属国家（或迷宫神器）教给他的能力，每种都有对应的特效。
- **地图瞬移**：地图可放大，点选任意位置后瞬移过去。
- **天气**（晴、多云、雨、雷暴、雾、酷热，寒冷地区降雪）、**动物**（12 种，可狩猎、可驯养，猛兽会咬人）、**恋爱**（村民先相恋再结婚、会分手；玩家可送花、约会、求婚）、**娱乐**（酒馆、庆典烟花、掷骰子）、**迷宫**（散布在世界各处，中心宝箱里有神器，有石像守卫）、**作弊面板**（使用后存档会被标记）。
- **多世界**、**一句话创建世界**、**照片 / GIF / 视频生成像素角色**（Apple Vision 本机识别）、**素材导入**、**内存预算与一键清理**。

哪些内容经过了验证、哪些没有，见 [docs/TESTING.md](docs/TESTING.md)。目前只在 CI 的 iOS 模拟器里运行过，没有真机验证。

## 许可

MIT，见 [LICENSE](LICENSE)。第三方组件见 [THIRD_PARTY.md](THIRD_PARTY.md)。
