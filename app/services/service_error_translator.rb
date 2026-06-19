# frozen_string_literal: true

module ServiceErrorTranslator
  EXACT = {
    "Invalid or expired verification token." => "验证链接无效或已过期。",
    "Invalid or expired reset token." => "重置链接无效或已过期。",
    "Recipient not found." => "找不到该用户。",
    "You cannot message yourself." => "不能给自己发私信。",
    "You cannot message this user." => "无法向该用户发送私信。",
    "New members cannot send private messages yet." => "新用户暂时无法发送私信，请多参与社区讨论。",
    "New members cannot post links. Participate more to unlock this." => "新用户暂时无法发送链接，请多参与社区讨论。",
    "Message is too short." => "消息内容不能为空。",
    "Not a participant." => "你不是此会话的参与者。",
    "Invalid parent post." => "无效的引用帖子。",
    "Slow mode is active. Please wait before posting again." => "当前处于慢速模式，请稍后再发帖。",
    "Please wait before posting again." => "请稍后再发帖。",
    "Invalid or expired link code." => "绑定码无效或已过期。",
    "Invalid connector signature." => "连接器签名无效。",
    "Server connector is not configured." => "服务器未配置连接器密钥。",
    "Invalid URL." => "链接无效。",
    "Invalid reaction." => "不支持该表情反应。",
    "Content not found." => "内容不存在或无权访问。",
    "Invalid email or password." => "邮箱或密码错误。",
    "Group title is required." => "请填写群组名称。",
    "Add at least one other participant." => "请至少添加一名其他成员。",
    "Too many participants." => "成员人数超出上限。",
    "You are not allowed to share this topic." => "无权分享该主题。",
    "Not a group conversation." => "此会话不是群组私信。",
    "User not found." => "找不到该用户。",
    "User is not a participant." => "该用户不是会话参与者。",
    "Not allowed." => "无权执行此操作。",
    "Cannot remove the last participant." => "不能移除最后一名参与者。",
    "Only participants can add members." => "仅参与者可添加成员。",
    "Group is full." => "群组人数已满。",
    "Only the group creator can add members." => "仅群主可添加新成员。",
    "User is already a participant." => "该用户已在群组中。",
    "Cannot add yourself." => "不能添加自己。",
    "Cannot message blocked user." => "无法向已拉黑的用户发送私信。",
    "User is silenced." => "该用户已被禁言。",
    "User cannot participate in private messages." => "该用户无法参与私信。",
    "Your cart is empty." => "购物车是空的。",
    "Order created." => "订单已创建。",
    "Report submitted." => "举报已提交。",
    "Reset token has expired." => "重置链接已过期。",
    "Email or token with new password is required." => "请提供邮箱，或提供重置令牌与新密码。",
    "You are not allowed to vote in this topic." => "你无权在此主题投票。",
    "Poll is closed." => "投票已关闭。",
    "No options selected." => "请至少选择一个选项。",
    "Too many options selected." => "选择的选项过多。",
    "Invalid option." => "无效的投票选项。",
    "Order cannot be cancelled." => "该订单无法取消。",
    "Payment is not refundable." => "该支付记录不可退款。",
    "Refund amount exceeds remaining balance." => "退款金额超过可退余额。",
    "Payment record not found." => "找不到支付记录。",
    "Payment is no longer valid." => "支付已失效。",
    "Order is not payable." => "订单当前不可支付。",
    "Order has no shippable items." => "订单中没有可发货的商品。",
    "You are not authorized to moderate this post." => "你无权审核此帖子。",
    "Unknown moderation action." => "未知的审核操作。",
    "Small action body is required." => "操作说明不能为空。",
    "Link code has already been used." => "绑定码已被使用。",
    "This Minecraft account is already linked." => "该 Minecraft 账号已绑定其他用户。",
    "Request timestamp is too old or invalid." => "请求时间戳无效或已过期。",
    "You are not allowed to create topics in this section." => "你无权在此分区发帖。",
    "Your trust level is too low to create topics in this section." => "信任等级不足，无法在此分区发帖。",
    "This section is read-only." => "此分区为只读。",
    "Title is required." => "请填写标题。",
    "Post body is too short." => "帖子内容过短。",
    "You are muted in this section." => "你在此分区已被禁言。",
    "Your account is banned." => "账户已被封禁。",
    "You are silenced and cannot post." => "你已被禁言，无法发帖。",
    "Please wait before creating another topic." => "请稍后再创建新主题。",
    "A similar topic was recently created." => "最近已有相似主题，请勿重复发帖。"
  }.freeze

  PATTERNS = [
    [ /\AYou cannot message (.+)\.\z/, "无法向 %s 发送私信。" ],
    [ /\ACannot message blocked user (.+)\.\z/, "对方已拉黑你，无法向 %s 发送私信。" ],
    [ /\AUsers not found: (.+)\z/, "找不到以下用户：%s" ]
  ].freeze

  module_function

  def translate(message)
    text = message.to_s.strip
    return text if text.blank?

    return EXACT[text] if EXACT.key?(text)

    PATTERNS.each do |pattern, template|
      match = text.match(pattern)
      return format(template, match[1]) if match
    end

    text
  end
end
