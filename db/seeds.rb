# frozen_string_literal: true

PERMISSIONS = [
  { key: "website.pages.read", name: "查看官网页面", category: "website" },
  { key: "website.pages.edit", name: "编辑官网页面", category: "website" },
  { key: "website.pages.publish", name: "发布官网页面", category: "website" },
  { key: "website.templates.manage", name: "管理前台模板", category: "website" },
  { key: "forum.sections.manage", name: "管理论坛分区", category: "forum" },
  { key: "forum.topics.lock", name: "锁定主题", category: "forum" },
  { key: "forum.topics.move", name: "移动主题", category: "forum" },
  { key: "forum.users.mute", name: "禁言用户", category: "forum" },
  { key: "forum.users.warn", name: "警告用户", category: "forum" },
  { key: "forum.badges.manage", name: "管理论坛徽章", category: "forum" },
  { key: "forum.tags.manage", name: "管理论坛标签", category: "forum" },
  { key: "store.products.manage", name: "管理商品", category: "store" },
  { key: "store.questions.answer", name: "官方回答商品问答", category: "store" },
  { key: "store.questions.manage", name: "管理商品问答", category: "store" },
  { key: "store.orders.read", name: "查看订单", category: "store" },
  { key: "store.orders.refund", name: "退款", category: "store" },
  { key: "minecraft.servers.manage", name: "管理 Minecraft 服务器", category: "minecraft" },
  { key: "minecraft.fulfillments.retry", name: "重试发货", category: "minecraft" },
  { key: "system.settings.manage", name: "管理系统设置", category: "system" },
  { key: "system.jobs.read", name: "查看后台任务", category: "system" },
  { key: "system.jobs.retry", name: "重试后台任务", category: "system" },
  { key: "system.audit.read", name: "查看审计日志", category: "system" },
  { key: "admin.access", name: "访问后台", category: "admin" }
].freeze

ROLES = {
  "owner" => {
    name: "所有者",
    description: "站点所有者，拥有全部权限",
    permissions: PERMISSIONS.map { |p| p[:key] }
  },
  "super_admin" => {
    name: "超级管理员",
    description: "除所有者外的最高管理权限",
    permissions: PERMISSIONS.map { |p| p[:key] } - [ "system.settings.manage" ]
  },
  "editor" => {
    name: "网站编辑",
    description: "管理官网内容",
    permissions: %w[website.pages.read website.pages.edit website.pages.publish website.templates.manage admin.access]
  },
  "forum_admin" => {
    name: "论坛管理员",
    description: "管理论坛",
    permissions: %w[forum.sections.manage forum.topics.lock forum.topics.move forum.users.mute forum.users.warn forum.badges.manage forum.tags.manage admin.access]
  },
  "moderator" => {
    name: "版主",
    description: "分区版主",
    permissions: %w[forum.topics.lock forum.users.mute forum.users.warn admin.access]
  },
  "store_admin" => {
    name: "商城管理员",
    description: "管理商城",
    permissions: %w[store.products.manage store.orders.read store.questions.answer store.questions.manage admin.access]
  },
  "finance" => {
    name: "财务",
    description: "订单与退款",
    permissions: %w[store.orders.read store.orders.refund admin.access]
  },
  "support" => {
    name: "客服",
    description: "客服支持",
    permissions: %w[store.orders.read admin.access]
  },
  "auditor" => {
    name: "只读审计员",
    description: "只读审计",
    permissions: %w[system.audit.read admin.access]
  }
}.freeze

puts "Seeding permissions and roles..."
PERMISSIONS.each do |attrs|
  Permission.find_or_create_by!(key: attrs[:key]) do |permission|
    permission.name = attrs[:name]
    permission.category = attrs[:category]
  end
end

ROLES.each do |key, attrs|
  role = Role.find_or_create_by!(key: key) do |r|
    r.name = attrs[:name]
    r.description = attrs[:description]
    r.system_role = true
  end

  attrs[:permissions].each do |permission_key|
    permission = Permission.find_by!(key: permission_key)
    role.permissions << permission unless role.permissions.include?(permission)
  end
end

InstallationLock.find_or_create_by!(id: 1) do |lock|
  lock.locked = false
end

SiteSetting.set("forum.bump_cooldown_hours", "24") unless SiteSetting.exists?(key: "forum.bump_cooldown_hours")
SiteSetting.set("forum.warning_mute_threshold", "10") unless SiteSetting.exists?(key: "forum.warning_mute_threshold")
SiteSetting.set("forum.warning_mute_days", "7") unless SiteSetting.exists?(key: "forum.warning_mute_days")
SiteSetting.set("forum.warning_block_post_threshold", "0") unless SiteSetting.exists?(key: "forum.warning_block_post_threshold")
SiteSetting.set("forum.warning_block_links_threshold", "0") unless SiteSetting.exists?(key: "forum.warning_block_links_threshold")
SiteSetting.set("forum.warning_block_pm_threshold", "0") unless SiteSetting.exists?(key: "forum.warning_block_pm_threshold")
SiteSetting.set("forum.report_auto_hide_threshold", "5") unless SiteSetting.exists?(key: "forum.report_auto_hide_threshold")
SiteSetting.set("forum.auto_close_on_solved", "0") unless SiteSetting.exists?(key: "forum.auto_close_on_solved")
SiteSetting.set("store.free_shipping_min_order_cents", "0") unless SiteSetting.exists?(key: "store.free_shipping_min_order_cents")
SiteSetting.set("store.flat_shipping_cents", "0") unless SiteSetting.exists?(key: "store.flat_shipping_cents")
SiteSetting.set("store.gift_wrap_cents", "500") unless SiteSetting.exists?(key: "store.gift_wrap_cents")
SiteSetting.set("store.min_checkout_subtotal_cents", "0") unless SiteSetting.exists?(key: "store.min_checkout_subtotal_cents")
SiteSetting.set("store.order_webhook_secret", "") unless SiteSetting.exists?(key: "store.order_webhook_secret")
SiteSetting.set("store.abandoned_cart_coupon_code", "") unless SiteSetting.exists?(key: "store.abandoned_cart_coupon_code")
SiteSetting.set("store.refund_window_days", "0") unless SiteSetting.exists?(key: "store.refund_window_days")
SiteSetting.set("store.pending_order_expiry_minutes", "30") unless SiteSetting.exists?(key: "store.pending_order_expiry_minutes")
SiteSetting.set("store.review_request_delay_days", "3") unless SiteSetting.exists?(key: "store.review_request_delay_days")
SiteSetting.set("forum.reaction_emojis", "👍,❤️,😂,🎉,👀") unless SiteSetting.exists?(key: "forum.reaction_emojis")
SiteSetting.set("forum.group_pm_creator_only_add", "false") unless SiteSetting.exists?(key: "forum.group_pm_creator_only_add")
SiteSetting.set("forum.saved_search_limit", "20") unless SiteSetting.exists?(key: "forum.saved_search_limit")
SiteSetting.set("forum.saved_search_digest_hour", "9") unless SiteSetting.exists?(key: "forum.saved_search_digest_hour")
SiteSetting.set("forum.saved_search_webhook_secret", "") unless SiteSetting.exists?(key: "forum.saved_search_webhook_secret")
SiteSetting.set("forum.saved_search_webhook_url", "") unless SiteSetting.exists?(key: "forum.saved_search_webhook_url")
SiteSetting.set("webhook.failure_alert_threshold", "5") unless SiteSetting.exists?(key: "webhook.failure_alert_threshold")
SiteSetting.set("webhook.failure_alert_forum_threshold", "5") unless SiteSetting.exists?(key: "webhook.failure_alert_forum_threshold")
SiteSetting.set("webhook.failure_alert_store_threshold", "5") unless SiteSetting.exists?(key: "webhook.failure_alert_store_threshold")
SiteSetting.set("webhook.failure_alert_email", "") unless SiteSetting.exists?(key: "webhook.failure_alert_email")
SiteSetting.set("webhook.failure_alert_cooldown_hours", "6") unless SiteSetting.exists?(key: "webhook.failure_alert_cooldown_hours")
SiteSetting.set("forum.digest_hour", "8") unless SiteSetting.exists?(key: "forum.digest_hour")
SiteSetting.set("store.order_webhook_url", "") unless SiteSetting.exists?(key: "store.order_webhook_url")
SiteSetting.set("store.compare_max_items", "4") unless SiteSetting.exists?(key: "store.compare_max_items")
SiteSetting.set("store.cart_max_items", "99") unless SiteSetting.exists?(key: "store.cart_max_items")
FeatureFlags.definitions.each do |definition|
  SiteSetting.set(definition.key, definition.default ? "true" : "false") unless SiteSetting.exists?(key: definition.key)
end
unless SiteSetting.exists?(key: "store.shipping_methods")
  SiteSetting.set("store.shipping_methods", Commerce::ShippingMethods::DEFAULT_JSON.to_json)
end

unless Website::Page.exists?
  theme = Website::Theme.find_or_create_by!(key: "default") do |t|
    t.name = "默认主题"
    t.tokens = {
      primary_color: "#2563eb",
      secondary_color: "#1e40af",
      background_color: "#0f172a",
      text_color: "#f8fafc",
      font_family: "system-ui, sans-serif",
      animations_enabled: true
    }
    t.active = true
  end

  page = Website::Page.find_or_create_by!(slug: "home") do |p|
    p.title = "欢迎来到我们的服务器"
    p.status = "published"
    p.page_type = "home"
    p.theme = theme
    p.published_at = Time.current
    p.seo = { title: "Minecraft 服务器", description: "最佳 Minecraft 生存服务器" }
  end

  Website::Block.find_or_create_by!(page: page, block_type: "hero", position: 0) do |b|
    b.settings = { headline: "欢迎来到 MCWeb 服务器", subheadline: "立即加入游戏", cta_text: "进入应用", cta_url: "/app/forum/sections" }
    b.visible = true
  end

  about_page = Website::Page.find_or_create_by!(slug: "about") do |p|
    p.title = "关于我们"
    p.status = "published"
    p.page_type = "custom"
    p.theme = theme
    p.published_at = Time.current
    p.seo = { title: "关于我们", description: "了解服务器与团队" }
  end

  Website::Block.find_or_create_by!(page: about_page, block_type: "hero", position: 0) do |b|
    b.settings = {
      headline: "关于 McWeb 服务器",
      subheadline: "我们致力于打造一个公平、有趣、长期运营的 Minecraft 社区。",
      cta_text: "加入论坛",
      cta_url: "/app/forum/sections"
    }
    b.visible = true
  end

  Website::Block.find_or_create_by!(page: about_page, block_type: "rich_text", position: 1) do |b|
    b.settings = {
      html: "<p>McWeb 是一套面向服主的开源官网系统，将营销页面、玩家论坛与数字商城整合在一起。</p><p>官网使用简洁路径如 <strong>/home</strong> 与 <strong>/about</strong>，玩家功能则集中在 <strong>/app</strong> 应用模块。</p>"
    }
    b.visible = true
  end

  [
    { label: "首页", page: nil, url: "/", position: 0 },
    { label: "服务器主页", page: page, position: 1 },
    { label: "关于", page: about_page, position: 2 },
    { label: "动态", page: nil, url: "/blog", position: 3 }
  ].each do |attrs|
    Website::NavItem.find_or_create_by!(location: "header", label: attrs[:label]) do |item|
      item.website_page_id = attrs[:page]&.id
      item.url = attrs[:url]
      item.position = attrs[:position]
      item.visible = true
    end
  end
end

if Rails.env.development?
  unless InstallationLock.locked?
    puts "Development mode: installation not locked. Visit /setup to initialize."
  end

  category = Community::Category.find_or_create_by!(slug: "general") do |c|
    c.name = "综合讨论"
    c.description = "综合话题"
  end

  Community::Section.find_or_create_by!(category: category, slug: "announcements") do |s|
    s.name = "公告"
    s.description = "服务器公告"
    s.position = 0
  end

  discussion_section = Community::Section.find_or_create_by!(category: category, slug: "product-discussion") do |s|
    s.name = "商品讨论"
    s.description = "商品相关讨论"
    s.position = 1
  end
  SiteSetting.set("store.product_discussion_section_slug", discussion_section.slug)

  store_category = Commerce::Category.find_or_create_by!(slug: "vip") do |c|
    c.name = "VIP"
  end

  Commerce::Product.find_or_create_by!(slug: "vip-monthly") do |p|
    p.category = store_category
    p.name = "VIP 月卡"
    p.description = "30 天 VIP 权限"
    p.product_type = "vip"
    p.status = "active"
    p.price_cents = 3000
    p.fulfillment_config = { commands: [ "lp user {player} parent addtemp vip 30d" ] }
  end

  Payments::ProviderConfig.find_or_create_by!(provider: "fake") do |c|
    c.enabled = true
    c.settings = { webhook_secret: "fake_webhook_secret" }
  end
end

puts "Ensuring builtin frontend template..."
Frontend::EnsureDefaultTemplate.call

puts "Seed complete."
