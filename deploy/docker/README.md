# 容器发布与启动合同

McWeb 的生产镜像使用三个明确角色：

| 角色 | 命令 | 数据库行为 |
| --- | --- | --- |
| 发布 | `release` | 执行一次 `db:prepare`；成功后可执行下游 `bin/docker-release` |
| Web | `web` | 只检查是否有待执行迁移，再启动 Puma |
| Worker | `worker` | 只检查是否有待执行迁移，再启动 Sidekiq |

只有发布角色可以修改 schema。Web 与 Worker 的检查只读；数据库不可达或存在
待执行迁移时，进程直接失败，不会继续启动应用或运行下游的数据库初始化。

## Docker Compose

`docker compose up` 会先运行一次 `mcweb-migrate`，成功后才启动 Web 与 Worker。
迁移失败时，两个长期进程都不会启动。不要删除
`service_completed_successfully` 依赖，也不要把 `db:prepare` 放回 Web 或 Worker。

## Kamal

`.kamal/hooks/pre-deploy` 使用已经交付的新镜像，只在主 Web 主机启动一个临时
`release` 容器。Kamal 的 hook 返回非零状态时会中止部署，因此迁移或下游发布步骤
失败都不会进入新容器启动阶段。

数据库必须在 `kamal setup` / `kamal deploy` 前已经可达。如果数据库由 Kamal
accessory 管理，首次部署前先单独启动该 accessory；不要用并行 Web 副本代替发布步骤。

## 直接运行镜像

不使用 Compose 或 Kamal 时，按顺序执行：

```bash
docker run --rm <相同的环境与卷参数> <image> release
docker run -d <相同的环境与卷参数> <image> web
docker run -d <相同的环境与卷参数> <image> worker
```

三个容器必须使用同一镜像版本和同一数据库配置。直接覆盖为历史命令
`bundle exec puma`、`bundle exec sidekiq` 或 Rails server 仍会执行待迁移检查，但不会
隐式迁移。

## 下游版本扩展

EE/EE-PVP 如需基于数据库生成发布产物，应提供可执行的 `bin/docker-release`。
它只会在 schema 准备成功后由发布角色调用一次。不要把这类工作放在 Puma、Sidekiq
或通用 Rails 启动分支中，否则多副本部署会重复执行并可能在迁移前读取旧 schema。
