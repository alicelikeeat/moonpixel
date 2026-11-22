# MoonPixel PC（Unreal 版）

游戏的全部逻辑（世界、国家、居民、模型）都在核心库 `MoonPixelBridge.dll` 里，由 iOS 版同一份 Swift 代码编译而成；Unreal 只负责画面。

## 第一次打开（大约 1 小时，大部分是下载）

1. **安装 Epic Games Launcher**，登录后在"虚幻引擎 → 库"里安装 **Unreal Engine 5.6**（或更新版本）。
2. **安装 Visual Studio 2022 Community**（免费），安装时勾选：
   - "使用 C++ 的游戏开发"（Game development with C++）
   - 右侧"Unreal Engine 安装程序"和"Windows 10/11 SDK"
3. **下载工程**：打开 https://github.com/alicelikeeat/moonpixel/releases/tag/pc-latest ，下载 `MoonPixel-PC.zip`，解压到路径**不含中文和空格**的地方（例如 `D:\MoonPixel-PC`）。
4. **双击 `MoonPixel.uproject`**。
   - 如果提示"引擎版本不同"，选择你装的版本即可。
   - 提示 "The following modules are missing or built with a different engine version... Would you like to rebuild them now?"，点 **Yes**。第一次编译需要几分钟。
5. 编辑器打开后，点上方的 **▶ Play（运行）**。

## 操作（第一版）

- **W A S D** 移动，**鼠标**转视角，**E / Q** 升降（自由飞行镜头）。
- 镜头周围的地形和建筑会自动加载；附近的居民会走路、干活、待机。

## 现在的状态（第一版：先跑通）

- 画面用的是顶点颜色，还没有动漫描边材质、光影和天空，看起来会比较朴素。下一步加上卡通渲染材质、天空和光照。
- 人物模型是现在的程序生成模型（临时占位），接入了骨骼动作；以后换成美术模型。
- 树、花、石头等"剪纸"物体暂时不显示。

## 遇到问题

- **编译失败**：把 Visual Studio 或编辑器里的错误信息截图发给我。
- **运行后一片空白或黑屏**：打开 菜单 → Window → Output Log（输出日志），搜索 `MoonPixel`，把那几行截图发给我。
