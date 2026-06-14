# 升级指南

## 推荐流程

使用项目自带脚本（需 root/sudo）：

```bash
sudo bin/update
```

脚本将：

1. 检查新版本与兼容性
2. 升级前自动备份数据库与上传文件
3. 解压到 `/opt/mcweb/releases/<version>` 并切换 `current` 软链接
4. 执行 `db:migrate` 与资源预编译
5. 顺序重启 Worker 与 Web
6. 健康检查；失败时可 `bin/rollback`

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
