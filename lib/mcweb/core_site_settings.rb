# frozen_string_literal: true

module Mcweb
  module CoreSiteSettings
    NAMESPACES = {
      "general." => { owner: "admin.system.settings.basic", surface: :basic },
      "site." => { owner: "admin.system.settings.basic", surface: :basic },
      "features." => { owner: "admin.system.feature_toggles", surface: :dedicated },
      "frontend." => { owner: "admin.frontend.templates", surface: :dedicated },
      "forum." => { owner: "admin.forum.settings", surface: :dedicated },
      "store." => { owner: "admin.store.settings", surface: :dedicated },
      "minecraft." => { owner: "admin.minecraft.settings", surface: :dedicated },
      "security." => { owner: "admin.system.rate_limits", surface: :dedicated },
      "webhook." => { owner: "admin.forum.settings", surface: :dedicated },
      "integrations." => { owner: "admin.system.integrations", surface: :dedicated },
      "identity." => { owner: "admin.identity.security", surface: :dedicated },
      "operations." => { owner: "admin.system.operations", surface: :internal },
      "api." => { owner: "admin.system.rate_limits", surface: :dedicated },
      "website." => { owner: "admin.website.content", surface: :dedicated }
    }.freeze

    FEATURE_KEYS = %w[
      features.forum.enabled
      features.minecraft.enabled
      features.store.enabled
      features.website_blog.enabled
    ].freeze

    FORUM_BOOLEAN_KEYS = %w[
      forum.allow_op_close
      forum.group_pm_creator_only_add
      forum.profile_posts_enabled
      forum.signatures_enabled
    ].freeze
    FORUM_INTEGER_KEYS = %w[
      forum.attachments.max_size_mb
      forum.attachments.scan_batch_size
      forum.bump_cooldown_hours
      forum.digest_hour
      forum.edit_grace_period_minutes
      forum.flag_abuse_threshold
      forum.group_pm_max_participants
      forum.max_daily_reactions
      forum.max_reactions_per_minute
      forum.max_reports_per_hour
      forum.max_upload_size_mb
      forum.min_trust_level_pm
      forum.min_trust_level_profile_post
      forum.min_trust_level_reaction
      forum.min_trust_level_signature
      forum.new_topic_window_days
      forum.report_auto_hide_threshold
      forum.require_post_approval_below_tl
      forum.saved_search_digest_hour
      forum.saved_search_limit
      forum.search_feeds_opml_history_limit
      forum.search_feeds_opml_saved_limit
      forum.signature_max_length
      forum.upload_cleanup.batch_size
      forum.warning_block_links_threshold
      forum.warning_block_pm_threshold
      forum.warning_block_post_threshold
      forum.warning_mute_days
      forum.warning_mute_threshold
      forum.warning_points_expire_days
      forum.warning_suspend_days
      forum.warning_suspend_threshold
    ].freeze
    FORUM_STRING_KEYS = %w[
      forum.attachments.allowed_extensions
      forum.attachments.scanner
      forum.event_webhook_events
      forum.extra_report_reasons
      forum.reaction_emojis
      forum.reaction_scores
    ].freeze

    STORE_INTEGER_KEYS = %w[
      store.cart_max_items
      store.compare_max_items
      store.flat_shipping_cents
      store.free_shipping_min_order_cents
      store.gift_wrap_cents
      store.min_checkout_subtotal_cents
      store.pending_order_expiry_minutes
      store.refund_window_days
      store.review_request_delay_days
    ].freeze
    STORE_STRING_KEYS = %w[
      store.abandoned_cart_coupon_code
      store.product_discussion_section_slug
      store.seo_description
      store.seo_title
      store.tax_code
      store.tax_country
      store.tax_region
    ].freeze
    STORE_FEATURE_KEYS = %w[
      store.features.gift_wrap
      store.features.order_shipping_management
      store.features.physical_products
      store.features.shipping
    ].freeze

    MINECRAFT_BOOLEAN_KEYS = %w[
      minecraft.backup.enabled
      minecraft.commerce.pause_fulfill_during_maintenance
      minecraft.graceful_stop.enabled
    ].freeze
    MINECRAFT_INTEGER_KEYS = %w[
      minecraft.graceful_stop.countdown_seconds
      minecraft.primary_account.cooldown_seconds
      minecraft.primary_account.request_expiry_hours
    ].freeze
    MINECRAFT_STRING_KEYS = %w[
      minecraft.backup.schedule
      minecraft.bridges.enabled
      minecraft.bridges.placeholders
      minecraft.exec_command.allowed_prefixes
      minecraft.graceful_stop.commands
      minecraft.graceful_stop.message
      minecraft.link_code_message
      minecraft.link_command
      minecraft.link_failed_message
      minecraft.link_success_message
      minecraft.profile.sections
      minecraft.whois_failed_message
    ].freeze

    RATE_LIMIT_ACTIONS = %w[
      login
      minecraft_identity_unlink
      preview
      private_message
      reaction
      registration
      reply
      report
      search
      search_suggest
      topic
      upload
    ].freeze

    module_function

    def register!(registry = Mcweb::SettingsNamespaceRegistry)
      NAMESPACES.each do |prefix, attributes|
        registry.register(prefix:, **attributes)
      end

      register_basic_settings(registry)
      register_dedicated_settings(registry)
      register_internal_settings(registry)
      registry
    end

    def register_basic_settings(registry)
      site_name_constraints = {
        required: true,
        strip: true,
        max_length: 80,
        reject_control_characters: true
      }
      %w[general.site_name site.name].each do |key|
        registry.register_setting(
          key:,
          type: :string,
          surface: :basic,
          constraints: site_name_constraints
        )
      end
      registry.register_setting(
        key: "site.url",
        type: :url,
        surface: :basic,
        constraints: { allow_blank: true, origin_only: true, strip: true }
      )
    end

    def register_dedicated_settings(registry)
      register_keys(registry, FEATURE_KEYS, type: :boolean)
      register_keys(
        registry,
        %w[frontend.active_portal_template frontend.active_website_template],
        type: :string,
        constraints: { strip: true, max_length: 128 }
      )

      register_keys(registry, FORUM_BOOLEAN_KEYS, type: :boolean)
      registry.register_setting(
        key: "forum.auto_close_on_solved",
        type: :boolean,
        constraints: { true_value: "1", false_value: "0" }
      )
      register_keys(
        registry,
        FORUM_INTEGER_KEYS,
        type: :integer,
        constraints: { min: 0, max: 1_000_000 }
      )
      register_keys(
        registry,
        %w[
          forum.points.daily_check_in
          forum.points.post_created
          forum.points.reaction_received
          forum.points.solution_accepted
        ],
        owner: "admin.forum.points",
        type: :integer,
        constraints: { min: -1_000_000, max: 1_000_000 }
      )
      register_keys(registry, FORUM_STRING_KEYS, type: :string)
      register_keys(
        registry,
        %w[forum.event_webhook_url forum.saved_search_webhook_url],
        type: :url,
        constraints: { allow_blank: true, strip: true }
      )
      register_keys(
        registry,
        %w[forum.event_webhook_secret forum.saved_search_webhook_secret],
        type: :string,
        sensitivity: :secret,
        constraints: { max_length: 4_096 }
      )

      register_keys(registry, STORE_FEATURE_KEYS, type: :boolean)
      register_keys(
        registry,
        STORE_INTEGER_KEYS,
        type: :integer,
        constraints: { min: 0, max: 1_000_000_000 }
      )
      register_keys(registry, STORE_STRING_KEYS, type: :string)
      registry.register_setting(
        key: "store.shipping_methods",
        type: :json,
        constraints: { kind: :array }
      )
      registry.register_setting(
        key: "store.order_webhook_url",
        type: :url,
        constraints: { allow_blank: true, strip: true }
      )
      registry.register_setting(
        key: "store.order_webhook_secret",
        type: :string,
        sensitivity: :secret,
        constraints: { max_length: 4_096 }
      )

      register_keys(registry, MINECRAFT_BOOLEAN_KEYS, type: :boolean)
      register_keys(
        registry,
        MINECRAFT_INTEGER_KEYS,
        type: :integer,
        constraints: { min: 0, max: 31_536_000 }
      )
      register_keys(registry, MINECRAFT_STRING_KEYS, type: :string)
      registry.register_setting(
        key: "minecraft.profile.skin_mode",
        type: :enum,
        constraints: { in: %w[2d 3d] }
      )
      registry.register_setting(
        key: "minecraft.primary_account.switch_policy",
        type: :enum,
        constraints: { in: %w[immediate staff_approval administrator_only] }
      )
      registry.register_setting(
        key: "minecraft.permission_group_mappings",
        owner: "admin.minecraft.permission_group_mappings",
        type: :json,
        constraints: { kind: :array }
      )

      register_keys(
        registry,
        %w[
          webhook.failure_alert_cooldown_hours
          webhook.failure_alert_forum_threshold
          webhook.failure_alert_store_threshold
          webhook.failure_alert_threshold
        ],
        type: :integer,
        constraints: { min: 0, max: 1_000_000 }
      )
      registry.register_setting(
        key: "webhook.failure_alert_email",
        type: :email,
        constraints: { allow_blank: true, strip: true }
      )
      registry.register_setting(
        key: "webhook.failure_alert_locale",
        type: :locale,
        constraints: { in: %w[zh-CN en] }
      )

      registry.register_setting(
        key: "api.rate_limit_per_minute",
        type: :integer,
        constraints: { min: 0, max: 100_000 }
      )
      register_rate_limit_settings(registry)

      registry.register_setting(
        key: "website.content_recovery.retention_days",
        type: :integer,
        constraints: { min: 1, max: 3_650 }
      )
    end

    def register_internal_settings(registry)
      registry.register_setting(
        key: "forum.online_peak_at",
        owner: "community.online_peak",
        surface: :internal,
        type: :timestamp,
        writable: false
      )
      registry.register_setting(
        key: "forum.online_peak_count",
        owner: "community.online_peak",
        surface: :internal,
        type: :integer,
        writable: false,
        constraints: { min: 0 }
      )
      registry.register_setting(
        key: "forum.vapid_public_key",
        owner: "community.web_push",
        surface: :internal,
        type: :string,
        writable: false
      )
      registry.register_setting(
        key: "forum.vapid_private_key",
        owner: "community.web_push",
        surface: :internal,
        type: :string,
        sensitivity: :secret,
        writable: false
      )
      %w[site group account].each do |scope|
        %w[bytes count hourly_count].each do |metric|
          registry.register_setting(
            key: "forum.upload_quota.#{scope}.#{metric}",
            owner: "community.upload_quota",
            surface: :internal,
            type: :integer,
            writable: false,
            constraints: {
              min: 0,
              max: metric == "bytes" ? 10_000_000_000_000_000 : 100_000_000
            }
          )
        end
      end
      registry.register_setting(
        key: "webhook.failure_alert_last_sent_at",
        owner: "operations.webhook_failure_alerts",
        surface: :internal,
        type: :timestamp,
        writable: false
      )
    end

    def register_rate_limit_settings(registry)
      RATE_LIMIT_ACTIONS.each do |action|
        %w[account ip].each do |dimension|
          registry.register_setting(
            key: "security.rate_limits.#{action}.#{dimension}_limit",
            type: :integer,
            constraints: { min: 0, max: 100_000 }
          )
          registry.register_setting(
            key: "security.rate_limits.#{action}.#{dimension}_window_seconds",
            type: :integer,
            constraints: { min: 1, max: 2_592_000 }
          )
        end
      end
    end

    def register_keys(registry, keys, **attributes)
      keys.each { |key| registry.register_setting(key:, **attributes) }
    end
    private_class_method :register_basic_settings,
      :register_dedicated_settings,
      :register_internal_settings,
      :register_rate_limit_settings,
      :register_keys
  end
end
