# Connector 协议

## 认证

每个请求需携带：

- `X-Connector-Signature`: HMAC-SHA256(secret, "#{timestamp}.#{body}")
- `X-Connector-Timestamp`: Unix 时间戳（±5 分钟有效）

## 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/minecraft/connector/:server_id/heartbeat` | 心跳 |
| GET | `/minecraft/connector/:server_id/tasks` | 拉取待执行任务 |
| POST | `/minecraft/connector/:server_id/tasks/:id/complete` | 回报执行结果 |

## 账号绑定

1. 游戏内 `/website link` 生成 8 位验证码（10 分钟有效）
2. 玩家在网站 `/minecraft/link` 输入验证码
3. 绑定 UUID，验证码一次性使用

## 发货幂等

- 每个发货任务携带全局唯一 `delivery_id`
- 插件本地持久化已处理的 `delivery_id`
- 重复任务返回已处理状态，不重复执行
