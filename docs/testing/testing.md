# 测试 / Testing

测试不依赖任何第三方框架：`tests/run_tests.gd` 加载 `tests/test_*.gd` 并运行其中的 `test_*` 方法。

```bash
export GODOT=/path/to/godot-4.3
$GODOT --headless --path . --import
tools/gd.sh 600 tests/run_tests.gd
tools/gd.sh 600 tests/run_tests.gd -- --filter=open_world
```

`tools/gd.sh <秒> <脚本>` 给每次运行加硬超时——脚本解析失败时 Godot 不会自行退出。

| 套件 | 覆盖 |
| --- | --- |
| `test_content` | 数据文件交叉引用、内容规模下限、地块 id 契约 |
| `test_open_world` | 内存预算查询与手动覆盖；任意坐标 / 任意顺序生成一致；负坐标读写；缓存不超预算且保留固定区块；被修改区块回收后可恢复；勘测不生成地形且可存读；回收期间作物继续生长 |
| `test_society` | ≥100 名可交互 NPC；3 年内有出生、死亡、配对、≥8 座建筑、>500 个地块；房屋墙体真实存在于世界；伴侣关系互指；无人卡在墙里；存读往返；人口下限迁入 |
| `test_worldgen` | 固定尺寸世界：确定性、区块顺序无关、三种规模、四类生物群系、生成耗时 |

最近一次本地结果：22 个测试、633 项断言全部通过，约 30 秒（Linux，Godot 4.3）。

尚未覆盖：渲染 / HUD（只做过截图人工检查）、长时间运行、真实移动设备。
