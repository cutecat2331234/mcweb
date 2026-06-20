# Minecraft 资源包与商城贴图

McWeb 可通过 `config/image_packs.yml` 引用本机 Minecraft 资源包或 Mod 材质目录，在商城等页面展示自定义物品图标（例如 JapariCraft 等 Mod 物品）。

## 配置

1. 复制示例文件：

```bash
cp config/image_packs.yml.example config/image_packs.yml
```

2. 编辑 `packs.<id>.root`，指向资源包内 `textures` 目录的绝对路径。例如 JapariCraft：

```yaml
packs:
  japaricraft:
    label: JapariCraft
    namespace: japaricraft
    root: /srv/minecraft/resourcepacks/JapariCraft/assets/japaricraft/textures
```

3. 重启应用。`Mcweb::ImagePackRegistry.ensure_config!` 会在启动时自动从示例生成 `image_packs.yml`（若尚不存在），缺失目录不会导致启动失败。

## API

```ruby
Mcweb::ImagePackRegistry.find("japaricraft")
Mcweb::ImagePackRegistry.texture_path("japaricraft", "item", "japariman")
# => "/srv/.../textures/item/japariman.png" when file exists
```

`frontend_hash` 可暴露各 pack 是否已挂载（`available: true/false`），供前端决定是否展示 Mod 图标。

## 与 Connector / 发货无关

资源包配置仅影响网站展示层，不参与 `Minecraft::DispatchFulfillmentJob` 或游戏内命令发货。

## 环境变量

| 变量 | 说明 |
|------|------|
| `MCWEB_IMAGE_PACKS_PATH` | 覆盖默认 `config/image_packs.yml` 路径 |
| `MCWEB_IMAGE_PACKS_EXAMPLE_PATH` | 覆盖示例文件路径 |
