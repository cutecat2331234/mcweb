---
title: 插件边界与选择
description: 在大应用、可信 Ruby 插件、REST API 和 Webhook 之间选择受支持的扩展方式。
edition: ce
audience:
  - plugin-developer
sidebar:
  order: 1
---

McWeb 插件是在部署环境中运行的可信 Ruby 代码。manifest 中的 capability 用于兼容性和审计，不是安全沙箱，也不能阻止插件访问宿主进程资源。

## 选择扩展方式

- 需要宿主内事务、稳定事件、设置或后台任务时，使用 [Plugin SDK](/docs/plugin-development/sdk/)。
- 需要独立部署、跨语言或低信任边界时，优先使用 [REST API](/docs/plugin-development/rest-api/) 和签名 Webhook。
- 需要较大的同仓业务模块时，使用大应用边界，不把它伪装成小型插件。

不要通过 monkey patch、未公开常量、深层前端依赖或直接数据库写入绕过宿主 API。升级前在目标 McWeb 版本上运行插件校验和测试。
