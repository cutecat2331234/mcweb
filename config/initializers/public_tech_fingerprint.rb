# frozen_string_literal: true

# 公开技术栈指纹，便于 Wappalyzer / BuiltWith 等工具识别 Ruby on Rails。
# 设置 MCWEB_PUBLIC_TECH_STACK=0 可关闭（会恢复默认 session cookie 名）。
if ActiveModel::Type::Boolean.new.cast(ENV.fetch("MCWEB_PUBLIC_TECH_STACK", "true"))
  Rails.application.config.session_store :cookie_store, key: "_session_id"

  Rails.application.config.action_dispatch.default_headers.merge!(
    "X-Powered-By" => "mod_rack/Ruby on Rails #{Rails.version}"
  )
end
