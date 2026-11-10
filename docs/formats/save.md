# 存档格式 / Save format

目录 `user://open_world/`：

| 文件 | 内容 |
| --- | --- |
| `index.json` | `world`（seed、时间、勘测区域）、`society`（全部村民与村落）、玩家位置 |
| `chunks/c_<cx>_<cy>.bin` | 仅保存被修改过的区块 |

区块文件：`"MPCK"` 魔数 · u16 格式版本 · u32 原始长度 · u32 压缩长度 · 16 字节 MD5 · ZSTD 压缩的 Variant 字典
（4 个地块层、摆件、容器、生长计时器）。截断或损坏的文件会被 `ChunkData.from_bytes` 拒绝。

写入一律先写 `<name>.tmp`、回读校验、把旧文件改名为 `.bak`，再把 tmp 改名到位（`SaveService.atomic_write`）。

地块的数值 id 定义在 `content/tiles/tiles.json`，属于存档契约：**不得重编号或复用**。

固定尺寸世界使用的事务式存档（日志、崩溃前滚、v1→v2 迁移）实现在 `SaveService` / `SaveMigrations`，尚无测试。
