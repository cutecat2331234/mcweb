# frozen_string_literal: true

module Mcweb
  # 统一描述 McWeb 的「平台内核」「大应用」「插件扩展」三层边界。
  #
  # - 平台内核：随 McWeb 发行版自带，不可卸载；提供身份、官网、支付适配、运维等基础能力。
  # - 大应用：一等公民业务模块，拥有独立模型/迁移/路由/后台；可整体开关，但代码在 monolith 内。
  # - 插件扩展：在不改 McWeb 核心业务代码的前提下扩展「原版」能力；权限与数据面受限。
  #
  # 注意：本注册表描述架构边界，不是第三方可热插拔的 Ruby 插件加载器。
  class ApplicationRegistry
    PlatformModule = Data.define(
      :id, :label, :description, :ruby_namespaces, :always_on
    )

    Application = Data.define(
      :id, :label, :description, :ruby_namespaces, :feature_flag_id,
      :admin_module_key, :path_prefixes, :permission_keys
    )

    Extension = Data.define(
      :id, :label, :description, :kind, :host, :capabilities, :limitations
    )

    PLATFORM_MODULES = [
      PlatformModule.new(
        id: :identity,
        label: "身份与权限",
        description: "注册登录、会话、RBAC、TOTP、审计",
        ruby_namespaces: %w[Identity],
        always_on: true
      ),
      PlatformModule.new(
        id: :website,
        label: "官网 CMS",
        description: "区块化页面、文章、导航、SEO",
        ruby_namespaces: %w[Website],
        always_on: true
      ),
      PlatformModule.new(
        id: :admin,
        label: "管理后台壳层",
        description: "仪表盘、用户/角色、模块授权入口",
        ruby_namespaces: %w[Admin],
        always_on: true
      ),
      PlatformModule.new(
        id: :payments,
        label: "支付基础设施",
        description: "Provider 抽象、Webhook 幂等、Lockbox 密钥",
        ruby_namespaces: %w[Payments],
        always_on: true
      ),
      PlatformModule.new(
        id: :operations,
        label: "运维",
        description: "健康检查、安装向导、Sidekiq 监控",
        ruby_namespaces: %w[Operations Setup],
        always_on: true
      ),
      PlatformModule.new(
        id: :frontend_templates,
        label: "前台模板引擎",
        description: "ZIP 模板安装、token/slot、只读资源路由",
        ruby_namespaces: %w[Frontend],
        always_on: true
      )
    ].freeze

    APPLICATIONS = [
      Application.new(
        id: :forum,
        label: "论坛",
        description: "社区分区、主题帖、私信、通知、版主工具",
        ruby_namespaces: %w[Community],
        feature_flag_id: :forum,
        admin_module_key: "forum",
        path_prefixes: [ "/app/forum" ],
        permission_keys: Identity::AccountAccess::ADMIN_MODULES.fetch("forum")
      ),
      Application.new(
        id: :store,
        label: "商城",
        description: "商品、购物车、订单、优惠券、履约与退款",
        ruby_namespaces: %w[Commerce],
        feature_flag_id: :store,
        admin_module_key: "store",
        path_prefixes: [ "/app/store" ],
        permission_keys: Identity::AccountAccess::ADMIN_MODULES.fetch("store")
      ),
      Application.new(
        id: :minecraft,
        label: "Minecraft 联动",
        description: "账号绑定、Connector 任务、节点托管、发货编排",
        ruby_namespaces: %w[Minecraft],
        feature_flag_id: :minecraft,
        admin_module_key: "minecraft",
        path_prefixes: [ "/app/minecraft", "/minecraft" ],
        permission_keys: Identity::AccountAccess::ADMIN_MODULES.fetch("minecraft")
      ),
      Application.new(
        id: :website_blog,
        label: "官网博客入口",
        description: "官网导航中的动态/博客区块（依赖 Website CMS）",
        ruby_namespaces: %w[Website],
        feature_flag_id: :website_blog,
        admin_module_key: "website",
        path_prefixes: [ "/blog" ],
        permission_keys: Identity::AccountAccess::ADMIN_MODULES.fetch("website")
      )
    ].freeze

    EXTENSIONS = [
      Extension.new(
        id: :mcweb_connector,
        label: "McWeb Connector",
        description: "部署在 Bukkit/Velocity/Bungee 上的 JVM 插件，通过 HTTP 与 Rails 通信",
        kind: :game_server_plugin,
        host: "plugins/mcweb-connector",
        capabilities: %w[
          heartbeat presence link_codes task_polling command_execution
          profile_fields permission_groups events
        ],
        limitations: [
          "不能直连 PostgreSQL",
          "不能新增 Rails 路由或模型",
          "任务类型与协议由 CONNECTOR_PROTOCOL.md 固定"
        ]
      ),
      Extension.new(
        id: :mcweb_node,
        label: "McWeb Node",
        description: "宿主机 Go Agent，托管 MC 进程并代理 Connector 流量",
        kind: :host_agent,
        host: "nodes/mcweb-node",
        capabilities: %w[
          process_drivers metrics backup_world sync_files connector_proxy
        ],
        limitations: [
          "不能修改论坛/商城业务逻辑",
          "任务执行受 Node 协议与 driver 白名单约束"
        ]
      ),
      Extension.new(
        id: :frontend_template_zip,
        label: "ZIP 前台模板",
        description: "上传 manifest.json + CSS/HTML 插槽，定制视觉",
        kind: :presentation,
        host: "public/template-starter",
        capabilities: %w[tokens css_slots logo favicon],
        limitations: [
          "不能改 Vue 页面结构或路由",
          "禁止 .vue/.rb/.js 进入模板包",
          "插槽 HTML 经消毒白名单"
        ]
      ),
      Extension.new(
        id: :outbound_webhooks,
        label: "出站 Webhook",
        description: "论坛保存搜索、商城订单等事件推送到外部 URL",
        kind: :integration,
        host: "SiteSetting + Jobs",
        capabilities: %w[signed_payload retry delivery_log],
        limitations: [
          "单向出站，外部系统不能注入 McWeb 业务代码",
          "事件类型由核心枚举"
        ]
      ),
      Extension.new(
        id: :minecraft_integration_actions,
        label: "Minecraft 集成规则",
        description: "后台可配的 if-this-then-that 规则（如事件触发命令）",
        kind: :rule_engine,
        host: "Admin::Minecraft::IntegrationActions",
        capabilities: %w[conditional_actions audit_log],
        limitations: [
          "动作类型固定，不能注册任意 Ruby 代码",
          "不能新增数据库表"
        ]
      ),
      Extension.new(
        id: :store_subfeatures,
        label: "商城子功能开关",
        description: "在商城大应用内细粒度开关物流、实体商品等",
        kind: :feature_toggle,
        host: "Commerce::StoreFeatures",
        capabilities: %w[per_feature_site_settings],
        limitations: [
          "仅 Commerce 模块内有效",
          "不能新增商品类型或支付渠道"
        ]
      )
    ].freeze

    class << self
      def platform_modules
        PLATFORM_MODULES
      end

      def applications
        APPLICATIONS
      end

      def extensions
        EXTENSIONS
      end

      def find_application(id)
        applications.find { |app| app.id == id.to_sym }
      end

      def find_extension(id)
        extensions.find { |ext| ext.id == id.to_sym }
      end

      def application_enabled?(id)
        app = find_application(id)
        return false unless app

        FeatureFlags.enabled?(app.feature_flag_id)
      end

      def enabled_applications
        applications.select { |app| application_enabled?(app.id) }
      end

      def application_for_path(path)
        applications.find do |app|
          app.path_prefixes.any? { |prefix| path.start_with?(prefix) }
        end
      end

      def tier_for_path(path)
        return :application if application_for_path(path)

        :platform
      end

      def admin_catalog
        {
          platform: platform_modules.map { |mod| serialize_platform(mod) },
          applications: applications.map { |app| serialize_application(app) },
          extensions: extensions.map { |ext| serialize_extension(ext) }
        }
      end

      def freely_extensible?
        false
      end

      private

      def serialize_platform(mod)
        {
          id: mod.id.to_s,
          label: mod.label,
          description: mod.description,
          always_on: mod.always_on,
          ruby_namespaces: mod.ruby_namespaces
        }
      end

      def serialize_application(app)
        {
          id: app.id.to_s,
          label: app.label,
          description: app.description,
          enabled: application_enabled?(app.id),
          admin_module_key: app.admin_module_key,
          path_prefixes: app.path_prefixes,
          ruby_namespaces: app.ruby_namespaces,
          permission_keys: app.permission_keys
        }
      end

      def serialize_extension(ext)
        {
          id: ext.id.to_s,
          label: ext.label,
          description: ext.description,
          kind: ext.kind.to_s,
          host: ext.host,
          capabilities: ext.capabilities,
          limitations: ext.limitations
        }
      end
    end
  end
end
