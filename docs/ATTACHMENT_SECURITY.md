# 附件上传、扫描与隔离

论坛上传分为两条安全链路：

- 行内图片先由 `Community::ImageUploadInspector` 按服务端实际解码结果规范化，
  存储后只能通过 `/app/forum/uploads/:public_id` 读取。未绑定图片仅上传者可读；
  绑定后按对应帖子的可见性检查，不再向客户端暴露新的 Active Storage 签名地址。
- 可下载附件先由 `Community::AttachmentContentInspector` 校验实际字节、格式结构、
  大小和危险类型策略，再进入恶意文件扫描隔离。客户端 MIME 不参与信任判断。

## 图片解码与规范化

行内图片只接受 PNG 和 JPEG，并始终保存服务端生成的新字节：

- PNG 由 ChunkyPNG 完整解码后重新编码。
- JPEG 由 libvips 以 `fail_on: warning`、禁止 unlimited 解码的模式完整读取，
  应用 EXIF 方向、归一到 sRGB、移除元数据并以固定质量重新编码。同步路径仅接受
  自包含、带本地量化表和 Huffman 表的单扫描 baseline JPEG；
  progressive、缩略流与多扫描 JPEG 直接拒绝。
- JPEG 规范化在每个 Web 进程内串行执行，并关闭高 CPU 的 Huffman 优化。单边
  不得超过 8192 像素，总像素不得超过 800 万；输入和重编码输出都必须
  落在调用方的字节上限内。
- JPEG 额外验证只有一个完整图像流，拒绝拼接第二张图片、截断数据和 EOI 后尾随载荷。
- 解码器警告、非法色带、畸形结构、尺寸越界和任何重编码失败都按不可读图片拒绝。

生产镜像的 build 与 runtime 阶段都必须安装 `libvips42`。CI/发布任务必须安装
`libvips-dev` 并运行 JPEG 解码/重编码 smoke test；缺少 libvips 时应立即失败，
不能退回只检查 JPEG marker 的弱校验。

## 扫描器配置

生产环境默认 **fail closed**。未配置或不可用的扫描器会把附件保留在隔离状态，
附件不能绑定到帖子，也不能下载。必须在启动 Web 与 Sidekiq worker 前配置一种扫描器：

```bash
# 方案一：本机 ClamAV 命令
MCWEB_ATTACHMENT_SCANNER=clamav_command
MCWEB_CLAMAV_COMMAND=/usr/bin/clamscan

# 方案二：私网 clamd
MCWEB_ATTACHMENT_SCANNER=clamd_tcp
MCWEB_CLAMD_HOST=127.0.0.1
MCWEB_CLAMD_PORT=3310
```

命令适配器通过 argv 直接启动可执行文件，不经过 shell，也不会把用户文件名拼入命令。
TCP 适配器使用 clamd `INSTREAM` 协议，不向扫描服务暴露对象存储 URL。clamd 必须只在
可信私网监听，并由防火墙限制来源。

可选配置：

| 配置 | 默认值 | 说明 |
|---|---:|---|
| `MCWEB_ATTACHMENT_SCAN_TIMEOUT_SECONDS` | `60` | 单次扫描超时，允许 1–300 秒 |
| `forum.attachments.scan_max_attempts` | `5` | 最大扫描次数 |
| `forum.attachments.scan_retry_seconds` | `30` | 指数退避基数，单次最多退避 1 小时 |
| `forum.attachments.infected_retention_hours` | `24` | 感染文件隔离保留时间 |
| `forum.attachments.scan_error_retention_hours` | `168` | 重试耗尽后的错误隔离保留时间 |
| `forum.attachments.scan_batch_size` | `200` | 每分钟补扫批量 |

## 生命周期

`forum_uploads.scan_status` 只允许以下状态：

- `pending`：等待扫描或正在扫描，不能绑定、不能下载。
- `clean`：扫描通过，可以绑定和下载。
- `infected`：检测到恶意内容，立即隔离，保留期后自动清理 Blob 与附件记录。
- `error`：扫描器超时、离线或返回异常；自动退避重试，耗尽后进入错误隔离并按保留期清理。

上传时会立即投递 `Community::ScanPostAttachmentJob`。每分钟运行的
`Maintenance::ScanForumAttachmentsJob` 会补领漏投任务、超时 claim、可重试错误以及
迁移前的旧附件；`Maintenance::CleanupForumUploadsJob` 负责最终清理过期、未绑定和
隔离文件。任务均要求生产 Sidekiq/Redis 正常运行。

## 上线检查

1. 先安装并更新扫描引擎及病毒库，再配置上述环境变量。
2. 启动 worker，确认 `scan_forum_attachments` 和 `cleanup_forum_uploads` 只注册一次。
3. 在非生产环境验证干净样本、标准反病毒测试样本、扫描器断连、超时和恢复重试。
4. 监控 `community.attachment.scan_clean`、`scan_infected`、`scan_error` 事件和
   maintenance 队列积压。
5. 迁移前正文中已经公开过的 Active Storage 签名 URL 无法靠新代理立即撤销。
   新上传和再次绑定会使用受控代理；历史正文需单独批量改写，必要时评估轮换
   `secret_key_base` 对全部 Rails 签名令牌的影响后再执行，不能只为附件盲目轮换。
