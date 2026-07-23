# 升级指南

## 推荐流程

使用项目自带脚本（需 root/sudo）：

```bash
sudo bin/update
```

`bin/update` 将（就地升级当前 `current` 发布）：

1. 运行 `bin/backup` 备份数据库与上传文件
2. `bundle install`
3. 执行 `db:migrate`
4. 资源预编译（`assets:precompile`）
5. 重启 `mcweb-worker` 与 `mcweb-web`
6. 运行 `bin/doctor` 健康检查；失败时可 `bin/rollback`

> 解压到 `/opt/mcweb/releases/<version>` 并切换 `current` 软链接由发布包安装脚本
> `packaging/quick-install.sh` 完成，`bin/update` 本身不做解压与版本切换。

## 数据库迁移原则

- 先增加字段/表，新旧代码兼容运行
- 后台迁移数据后再删除旧字段
- 订单、支付、发货相关字段不得在普通升级中直接删除

## 手动升级

```bash
cd /opt/mcweb/current
sudo -u mcweb bundle install --deployment --without development test
sudo -u mcweb RAILS_ENV=production bin/rails db:migrate
sudo -u mcweb RAILS_ENV=production bin/rails assets:precompile
sudo systemctl restart mcweb-worker mcweb-web
```

## 回滚

```bash
sudo bin/rollback
```

保留最近若干 `releases` 目录以便快速回退。

## CI 自动构建

推送到 `main` 或手动触发 **Release Build** 工作流后，可在 Actions 产物中下载：

- `mcweb-<version>.tar.gz` — 完整可部署包（含 gems 与静态资源）
- `mcweb-<version>.tar.gz.sha256` — 校验文件

本地构建：

```bash
chmod +x bin/build-release packaging/quick-install.sh
RELEASE_VERSION=dev-local bin/build-release
```
