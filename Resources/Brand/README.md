# Sift 应用图标

![Sift](Sift.png)

`Sift.icon` 是应用图标的可编辑源文件，`Sift.png` 是 Icon Composer 原生渲染的 1024 × 1024 默认外观预览。应用名称与 bundle identifier 继续由 `Config/Info.plist` 管理。

## 编辑源资产

用 Icon Composer 打开 `Sift.icon`。工程内的三个透明 SVG 均为 1024 × 1024 同坐标画布，从后向前为：

1. `Assets/01-bottom-apricot.svg`：底部杏色带面。
2. `Assets/02-middle-lilac.svg`：中部淡紫带面及右折面。
3. `Assets/03-top-iris.svg`：顶部鸢尾紫带面及左折面。

三个图层放在同一个材质组中，使用 35% 中性投影。半透明和高光描边关闭，避免显露下层圆头和人为描出接缝。曲面明暗沿折弯角度分布，由 SVG 内的渐变弧片构成；这些内部弧片有微量重叠以避免抗锯齿缝隙。不要逐片添加描边或玻璃效果。

源 SVG 仅含闭合路径与线性渐变，没有背景、滤镜、蒙版或裁切路径。背景色 `#F6F7FA` 保存在 `icon.json` 中。

## 导出与打包

使用选中的完整 Xcode（支持 Icon Composer 的 Xcode 26 或更新版本）：

```bash
# 编辑源文件后更新仓库中的静态预览
./scripts/export-app-icon.sh

# 编译应用、编译图标资源、合并图标元数据，然后签名
./scripts/build-app.sh
```

打包脚本使用 `actool` 从 `Sift.icon` 生成 `Assets.car`、`Sift.icns` 和图标 Info.plist 字段，再放入 `dist/Mailroom.app`。生成文件保存在已忽略的 `dist/` 内；源文件和预览纳入版本控制。`Sift.icns` 是较旧 macOS 的兼容资源，支持新图标格式的系统可使用编译后的图层资源。

该图标接入的是 `.app` 打包流程。`swift run MailroomApp` 不创建带图标元数据的应用包。
