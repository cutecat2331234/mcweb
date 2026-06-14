# 安装指南

## 前置条件

- Ubuntu 22.04/24.04 或 Debian 12 x86_64
- root 或 sudo 权限
- 域名已解析到服务器
- 开放 80、443 端口

## 交互式安装

```bash
sudo bin/install
sudo -u mcweb /opt/mcweb/current/bin/setup
sudo systemctl enable --now mcweb-web mcweb-worker caddy
```

## 目录结构

| 路径 | 用途 |
|------|------|
| `/opt/mcweb/releases/<version>` | 应用发布版本 |
| `/opt/mcweb/current` | 当前版本软链接 |
| `/etc/mcweb` | 配置文件 |
| `/var/lib/mcweb/uploads` | 上传文件 |
| `/var/log/mcweb` | 日志 |
| `/var/backups/mcweb` | 备份 |

## 初始化向导

安装后访问 `/setup`：

1. 站点信息
2. 管理员账号
3. 完成后自动锁定安装入口

## 决策记录

- **Ruby 3.4.9 而非 4.0**：Rails 8.1 生态在 3.4.x 上最稳定；4.0 发布后将在下一版本评估升级
- **无 Docker 默认依赖**：降低服主部署门槛，使用 systemd + Caddy 原生部署
- **无 Redis 默认依赖**：Solid Queue/Cache 基于 PostgreSQL
