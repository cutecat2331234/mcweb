---
title: 安装后的首次配置
description: 完成 McWeb CE 安装后检查站点、管理员、后台任务、邮件、存储和 Minecraft 连接状态。
edition: ce
audience:
  - administrator
  - operator
sidebar:
  order: 2
---

本页从安装程序已经完成、站点可以响应 HTTP 请求的状态开始。部署方式和命令以你的发行包为准；生产环境不要复用开发凭据或示例密码。

## 1. 验证基本服务

1. 打开站点首页和管理后台，确认没有维护页或静态资源错误。
2. 使用安装时创建的管理员账户登录，确认角色和权限来自服务端，而不是仅靠隐藏菜单。
3. 检查数据库、缓存和后台任务进程均处于健康状态。
4. 发送一封测试邮件，并验证公开站点 URL、发件人和回调地址。

## 2. 完成安全设置

- 为管理员启用两步验证并安全保存恢复码。
- 检查公开注册、登录限流、上传限制和允许的文件类型。
- 若启用附件扫描，按[附件上传、扫描与隔离](/docs/operations/attachment-security/)完成扫描器和隔离目录检查。
- 若启用支付，先按[支付渠道配置与对账](/docs/operations/payment-provider/)完成连接和 Webhook 验证，再开放结账。

## 3. 建立可恢复基线

首次导入真实数据前创建备份，并完成一次隔离恢复验证。参见[生产备份、恢复、更新与回滚](/docs/operations/backup-release-rollback/)。

如果使用 Host Console 管理生命周期，继续阅读 [Host Console](/docs/operations/host-console/)。
