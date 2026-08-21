# frozen_string_literal: true

module Identity
  # Canonical catalog for permissions shipped by McWeb core.
  #
  # Plugin-contributed permissions remain owned by the plugin permission
  # catalog. Core callers should use this catalog instead of maintaining
  # parallel key lists in seeds, admin modules, and API serializers.
  class PermissionCatalog
    Entry = Data.define(
      :key,
      :category,
      :i18n_key,
      :status,
      :execution_points,
      :admin_module,
      :fallback_name,
      :fallback_description
    ) do
      def active?
        status == "active"
      end

      def reserved?
        status == "reserved"
      end
    end

    STATUSES = %w[active planned reserved].freeze
    ADMIN_MODULE_DOMAINS = %w[forum identity minecraft store system website].freeze

    build_entry = lambda do |key, fallback_name, status: "active", admin_module: :auto,
                            execution_points: [], fallback_description: nil|
      normalized_key = key.to_s
      category = normalized_key.split(".", 2).first
      normalized_status = status.to_s
      raise ArgumentError, "invalid permission status: #{normalized_status}" unless STATUSES.include?(normalized_status)

      resolved_admin_module =
        if admin_module == :auto
          category if ADMIN_MODULE_DOMAINS.include?(category)
        else
          admin_module&.to_s
        end

      Entry.new(
        key: normalized_key.freeze,
        category: category.freeze,
        i18n_key: "mcweb.permissions.#{normalized_key.tr('.', '_')}".freeze,
        status: normalized_status.freeze,
        execution_points: execution_points.map { |point| point.to_s.freeze }.freeze,
        admin_module: resolved_admin_module&.freeze,
        fallback_name: fallback_name.to_s.freeze,
        fallback_description: (fallback_description.presence || fallback_name).to_s.freeze
      ).freeze
    end

    ENTRIES = [
      build_entry.call(
        "store.payments.configure",
        "Configure payment providers",
        execution_points: [
          "app/controllers/admin/store/payment_providers_controller.rb#show",
          "app/controllers/admin/store/payment_providers_controller.rb#update",
          "app/services/payments/update_provider_configuration.rb#call"
        ]
      ),
      build_entry.call(
        "store.payments.connection_test",
        "Test payment-provider connections",
        execution_points: [
          "app/controllers/admin/store/payment_providers_controller.rb#test_connection",
          "app/services/payments/test_provider_connection.rb#call"
        ]
      ),
      build_entry.call(
        "store.payments.replay",
        "Payment webhook replay",
        execution_points: [
          "app/controllers/admin/store/payment_operations_controller.rb#replay",
          "app/services/payments/replay_webhook_event.rb#call"
        ]
      ),
      build_entry.call(
        "store.payments.late_review",
        "Late payment review",
        execution_points: [
          "app/models/payments/late_payment_case.rb",
          "app/controllers/admin/store/late_payment_cases_controller.rb#index",
          "app/controllers/admin/store/late_payment_cases_controller.rb#acknowledge",
          "app/services/payments/acknowledge_late_payment_case.rb#call"
        ]
      ),
      build_entry.call(
        "store.disputes.read",
        "View payment disputes",
        execution_points: [
          "app/controllers/admin/store/disputes_controller.rb#index",
          "app/controllers/admin/store/disputes_controller.rb#show"
        ]
      ),
      build_entry.call(
        "store.disputes.sensitive_read",
        "View sensitive dispute details",
        execution_points: [
          "app/controllers/admin/store/disputes_controller.rb#show",
          "app/controllers/admin/store/disputes_controller.rb#evidence_download_token",
          "app/controllers/admin/store/disputes_controller.rb#evidence_download"
        ]
      ),
      build_entry.call(
        "store.disputes.assign",
        "Assign payment disputes",
        execution_points: [
          "app/controllers/admin/store/disputes_controller.rb#execute_action",
          "app/services/commerce/disputes/execute_action.rb"
        ]
      ),
      build_entry.call(
        "store.disputes.note",
        "Add payment dispute notes",
        execution_points: [
          "app/controllers/admin/store/disputes_controller.rb#execute_action",
          "app/services/commerce/disputes/execute_action.rb"
        ]
      ),
      build_entry.call(
        "store.disputes.evidence_submit",
        "Submit payment dispute evidence",
        execution_points: [
          "app/controllers/admin/store/disputes_controller.rb#execute_action",
          "app/services/commerce/disputes/execute_action.rb"
        ]
      ),
      build_entry.call(
        "store.disputes.accept_loss",
        "Accept payment dispute losses",
        execution_points: [
          "app/controllers/admin/store/disputes_controller.rb#authorize_action",
          "app/controllers/admin/store/disputes_controller.rb#execute_action",
          "app/services/commerce/disputes/execute_action.rb"
        ]
      ),
      build_entry.call(
        "store.disputes.close",
        "Close payment disputes",
        execution_points: [
          "app/controllers/admin/store/disputes_controller.rb#execute_action",
          "app/services/commerce/disputes/execute_action.rb"
        ]
      ),
      build_entry.call(
        "store.disputes.rights_manage",
        "Manage disputed-order rights",
        execution_points: [
          "app/controllers/admin/store/disputes_controller.rb#authorize_action",
          "app/controllers/admin/store/disputes_controller.rb#execute_action",
          "app/services/commerce/disputes/execute_action.rb",
          "app/services/commerce/disputes/rights_policy.rb"
        ]
      ),
      build_entry.call(
        "store.payments.reconciliation.read",
        "View payment reconciliation",
        execution_points: [
          "app/models/payments/reconciliation_discrepancy.rb",
          "app/controllers/admin/store/payment_reconciliations_controller.rb#index"
        ]
      ),
      build_entry.call(
        "store.payments.reconciliation.review",
        "Review payment reconciliation discrepancies",
        execution_points: [
          "app/models/payments/reconciliation_discrepancy.rb",
          "app/controllers/admin/store/payment_reconciliations_controller.rb#review",
          "app/services/payments/review_reconciliation_discrepancy.rb#call"
        ]
      ),
      build_entry.call(
        "store.payments.reconciliation.run",
        "Run payment reconciliation",
        execution_points: [
          "app/controllers/admin/store/payment_reconciliations_controller.rb#trigger",
          "app/controllers/admin/store/payment_reconciliations_controller.rb#manual_authorization",
          "app/services/payments/request_manual_reconciliation.rb#call"
        ]
      ),
      build_entry.call(
        "website.pages.read",
        "查看官网页面",
        execution_points: [
          "app/controllers/admin/website/pages_controller.rb#index",
          "app/controllers/admin/website/pages_controller.rb#show",
          "app/controllers/admin/website/pages_controller.rb#preview"
        ]
      ),
      build_entry.call(
        "website.pages.edit",
        "编辑官网页面",
        execution_points: [
          "app/controllers/admin/website/pages_controller.rb#create",
          "app/controllers/admin/website/pages_controller.rb#update",
          "app/controllers/admin/website/pages_controller.rb#destroy",
          "app/controllers/admin/website/blocks_controller.rb"
        ]
      ),
      build_entry.call(
        "website.pages.publish",
        "发布官网页面",
        execution_points: [
          "app/controllers/admin/website/pages_controller.rb#publish",
          "app/controllers/admin/website/pages_controller.rb#schedule",
          "app/controllers/admin/website/themes_controller.rb#activate"
        ]
      ),
      build_entry.call(
        "website.articles.read",
        "查看官网文章",
        execution_points: [
          "app/controllers/admin/website/articles_controller.rb#index",
          "app/controllers/admin/website/articles_controller.rb#show",
          "app/controllers/admin/website/articles_controller.rb#preview"
        ]
      ),
      build_entry.call(
        "website.articles.edit",
        "编辑官网文章",
        execution_points: [
          "app/controllers/admin/website/articles_controller.rb#create",
          "app/controllers/admin/website/articles_controller.rb#update",
          "app/controllers/admin/website/articles_controller.rb#destroy"
        ]
      ),
      build_entry.call(
        "website.articles.publish",
        "发布官网文章",
        execution_points: [
          "app/controllers/admin/website/articles_controller.rb#publish",
          "app/controllers/admin/website/articles_controller.rb#schedule"
        ]
      ),
      build_entry.call(
        "website.templates.manage",
        "管理前台模板",
        execution_points: [
          "app/controllers/admin/frontend/templates_controller.rb",
          "app/controllers/concerns/frontend_template_share.rb"
        ]
      ),
      build_entry.call(
        "forum.sections.manage",
        "管理论坛分区",
        execution_points: [
          "app/controllers/admin/forum/categories_controller.rb",
          "app/controllers/admin/forum/sections_controller.rb"
        ]
      ),
      build_entry.call(
        "forum.sections.lifecycle",
        "归档与恢复论坛分区",
        execution_points: [
          "app/controllers/admin/forum/sections_controller.rb#lifecycle",
          "app/controllers/admin/forum/sections_controller.rb#archive",
          "app/controllers/admin/forum/sections_controller.rb#restore"
        ]
      ),
      build_entry.call(
        "forum.sections.delete",
        "永久删除论坛分区",
        execution_points: [
          "app/controllers/admin/forum/sections_controller.rb#destroy"
        ]
      ),
      build_entry.call(
        "forum.attachments.security.read",
        "查看附件安全状态",
        execution_points: [
          "app/controllers/admin/forum/attachments_controller.rb#index"
        ]
      ),
      build_entry.call(
        "forum.attachments.security.manage",
        "管理附件安全处置",
        execution_points: [
          "app/controllers/admin/forum/attachments_controller.rb#destroy",
          "app/controllers/admin/forum/attachments_controller.rb#prune_orphans",
          "app/controllers/admin/forum/attachments_controller.rb#retry_scan",
          "app/controllers/admin/forum/attachments_controller.rb#retry_cleanup"
        ]
      ),
      build_entry.call(
        "forum.attachments.security.release",
        "人工放行隔离附件",
        execution_points: [
          "app/controllers/admin/forum/attachments_controller.rb#release_quarantine",
          "app/services/community/release_quarantined_upload.rb#call"
        ]
      ),
      build_entry.call(
        "forum.topics.lock",
        "锁定主题",
        execution_points: [
          "app/controllers/admin/forum/topics_controller.rb",
          "app/services/community/section_moderation.rb"
        ]
      ),
      build_entry.call(
        "forum.posts.edit_others",
        "编辑他人帖子",
        execution_points: [
          "app/services/community/edit_post.rb#call",
          "app/services/community/section_moderation.rb#can_edit_post?"
        ]
      ),
      build_entry.call(
        "forum.topics.edit_others",
        "编辑他人主题",
        execution_points: [
          "app/services/community/section_moderation.rb#can_edit_topic?"
        ]
      ),
      build_entry.call(
        "forum.topics.move",
        "移动主题",
        execution_points: [
          "app/services/community/move_topic.rb#call",
          "app/services/community/merge_topics.rb#call",
          "app/services/community/split_topic.rb#call"
        ]
      ),
      build_entry.call(
        "forum.users.mute",
        "禁言用户",
        execution_points: [
          "app/controllers/admin/forum/mutes_controller.rb",
          "app/services/community/create_mute.rb#call",
          "app/services/community/remove_mute.rb#call"
        ]
      ),
      build_entry.call(
        "forum.users.warn",
        "警告用户",
        execution_points: [
          "app/controllers/admin/forum/warnings_controller.rb",
          "app/services/community/create_user_warning.rb#call"
        ]
      ),
      build_entry.call(
        "forum.users.trust.manage",
        "Manage forum trust levels",
        execution_points: [
          "app/controllers/admin/users_controller.rb#set_trust_level"
        ]
      ),
      build_entry.call(
        "forum.badges.manage",
        "管理论坛徽章",
        execution_points: [
          "app/controllers/admin/forum/badges_controller.rb"
        ]
      ),
      build_entry.call(
        "forum.tags.manage",
        "管理论坛标签",
        execution_points: [
          "app/controllers/admin/forum/tags_controller.rb",
          "app/controllers/admin/forum/tag_groups_controller.rb",
          "app/services/community/sync_topic_tags.rb"
        ]
      ),
      build_entry.call(
        "forum.points.manage",
        "管理论坛积分",
        execution_points: [
          "app/controllers/admin/forum/points_controller.rb"
        ]
      ),
      build_entry.call(
        "forum.conversations.create",
        "分享他人主题到私信",
        admin_module: nil,
        execution_points: [
          "app/services/community/share_topic_as_conversation.rb#can_share?"
        ]
      ),
      build_entry.call(
        "forum.conversations.reports.review",
        "Review private-message reports",
        execution_points: [
          "app/controllers/admin/forum/reports_controller.rb#index",
          "app/controllers/admin/forum/reports_controller.rb#show",
          "app/controllers/admin/forum/reports_controller.rb#reveal_evidence"
        ]
      ),
      build_entry.call(
        "store.products.manage",
        "管理商品",
        execution_points: [
          "app/controllers/admin/store/products_controller.rb",
          "app/controllers/admin/store/categories_controller.rb"
        ]
      ),
      build_entry.call(
        "store.products.read",
        "查看商城工作人员通知",
        admin_module: nil,
        execution_points: [
          "app/controllers/commerce/preferences_controller.rb#staff_notifications?",
          "app/jobs/commerce/notify_low_stock_staff_job.rb#perform"
        ]
      ),
      build_entry.call(
        "store.inventory.read",
        "View inventory ledger and anomalies",
        execution_points: [
          "app/controllers/admin/store/inventory_controller.rb#index",
          "app/services/commerce/inventory_health.rb#call"
        ]
      ),
      build_entry.call(
        "store.inventory.adjust",
        "Adjust inventory",
        execution_points: [
          "app/controllers/admin/store/inventory_controller.rb#authorize_adjustment",
          "app/controllers/admin/store/inventory_controller.rb#adjust",
          "app/services/commerce/inventory_adjustment.rb#call"
        ]
      ),
      build_entry.call(
        "store.inventory.recover",
        "Recover inventory anomalies",
        execution_points: [
          "app/controllers/admin/store/inventory_controller.rb#index"
        ]
      ),
      build_entry.call(
        "store.questions.answer",
        "官方回答商品问答",
        admin_module: nil,
        execution_points: [
          "app/controllers/commerce/product_questions_controller.rb#answer",
          "app/services/commerce/update_product_answer.rb#call",
          "app/services/commerce/delete_product_answer.rb#call",
          "app/services/commerce/notify_new_product_question.rb"
        ]
      ),
      build_entry.call(
        "store.questions.manage",
        "管理商品问答",
        execution_points: [
          "app/controllers/admin/store/product_questions_controller.rb"
        ]
      ),
      build_entry.call(
        "store.orders.read",
        "查看订单",
        execution_points: [
          "app/controllers/admin/store/orders_controller.rb",
          "lib/mcweb/plugin_api/v1/commerce.rb"
        ]
      ),
      build_entry.call(
        "store.finance.read",
        "View finance records",
        execution_points: [
          "app/controllers/admin/store/finance_controller.rb#index",
          "app/controllers/admin/store/finance_controller.rb#document",
          "app/services/commerce/finance_document_query.rb"
        ]
      ),
      build_entry.call(
        "store.finance.documents.manage",
        "Manage finance documents",
        execution_points: [
          "app/controllers/admin/store/finance_controller.rb#transition_document",
          "app/services/commerce/transition_finance_document.rb#call"
        ]
      ),
      build_entry.call(
        "store.finance.exports.create",
        "Create finance exports",
        execution_points: [
          "app/controllers/admin/store/finance_controller.rb#create_export",
          "app/controllers/admin/store/finance_controller.rb#revoke_export",
          "app/services/commerce/request_finance_export.rb#call",
          "app/jobs/commerce/build_finance_export_job.rb#perform"
        ]
      ),
      build_entry.call(
        "store.finance.exports.download",
        "Download finance exports",
        execution_points: [
          "app/controllers/admin/store/finance_controller.rb#download_export",
          "app/services/commerce/authorize_finance_export_download.rb#call"
        ]
      ),
      build_entry.call(
        "store.orders.refund",
        "退款",
        execution_points: [
          "app/controllers/admin/store/orders_controller.rb#process_refund",
          "app/controllers/admin/store/orders_controller.rb#reject_refund"
        ]
      ),
      build_entry.call(
        "store.orders.mark_paid",
        "Manually mark orders paid",
        execution_points: [
          "app/controllers/admin/store/orders_controller.rb#authorize_high_risk_action",
          "app/controllers/admin/store/orders_controller.rb#bulk_update",
          "app/services/commerce/high_risk_order_action.rb"
        ]
      ),
      build_entry.call(
        "store.orders.mark_fulfilled",
        "Manually mark orders fulfilled",
        execution_points: [
          "app/controllers/admin/store/orders_controller.rb#authorize_high_risk_action",
          "app/controllers/admin/store/orders_controller.rb#bulk_update",
          "app/services/commerce/high_risk_order_action.rb"
        ]
      ),
      build_entry.call(
        "store.orders.cancel",
        "Manually cancel orders",
        execution_points: [
          "app/controllers/admin/store/orders_controller.rb#authorize_high_risk_action",
          "app/controllers/admin/store/orders_controller.rb#bulk_update",
          "app/services/commerce/high_risk_order_action.rb"
        ]
      ),
      build_entry.call(
        "store.credit.read",
        "View member store credit",
        execution_points: [
          "app/controllers/admin/users_controller.rb#store_credit_index",
          "app/controllers/admin/users_controller.rb#store_credit_show"
        ]
      ),
      build_entry.call(
        "store.credit.adjust",
        "Adjust member store credit",
        execution_points: [
          "app/controllers/admin/users_controller.rb#authorize_store_credit_adjustment",
          "app/controllers/admin/users_controller.rb#adjust_store_credit",
          "app/services/commerce/store_credit_adjustment_authorization.rb#issue",
          "app/services/commerce/adjust_store_credit.rb#call"
        ]
      ),
      build_entry.call(
        "store.entitlements.read",
        "View member entitlements",
        execution_points: [
          "app/controllers/admin/store/user_memberships_controller.rb#index",
          "app/controllers/admin/store/user_memberships_controller.rb#show",
          "app/controllers/admin/store/user_entitlements_controller.rb#index",
          "app/controllers/admin/store/user_entitlements_controller.rb#show"
        ]
      ),
      build_entry.call(
        "store.entitlements.grant",
        "Grant member entitlements",
        execution_points: [
          "app/controllers/admin/store/user_memberships_controller.rb#create",
          "app/controllers/admin/store/user_entitlements_controller.rb#create",
          "app/services/commerce/high_risk_membership_action.rb",
          "app/services/commerce/high_risk_entitlement_action.rb"
        ]
      ),
      build_entry.call(
        "store.entitlements.revoke",
        "Revoke member entitlements",
        execution_points: [
          "app/controllers/admin/store/user_memberships_controller.rb#revoke",
          "app/controllers/admin/store/user_entitlements_controller.rb#revoke",
          "app/services/commerce/high_risk_membership_action.rb",
          "app/services/commerce/high_risk_entitlement_action.rb"
        ]
      ),
      build_entry.call(
        "minecraft.servers.manage",
        "管理 Minecraft 服务器",
        execution_points: [
          "app/controllers/admin/minecraft/servers_controller.rb",
          "app/controllers/admin/minecraft/settings_controller.rb"
        ]
      ),
      build_entry.call(
        "minecraft.nodes.manage",
        "管理 Minecraft 节点",
        execution_points: [
          "app/controllers/admin/minecraft/nodes_controller.rb"
        ]
      ),
      build_entry.call(
        "minecraft.servers.control",
        "远程控制 Minecraft 服务器",
        execution_points: [
          "app/controllers/admin/minecraft/servers_controller.rb#start",
          "app/controllers/admin/minecraft/servers_controller.rb#stop",
          "app/controllers/admin/minecraft/servers_controller.rb#restart",
          "app/controllers/admin/minecraft/servers_controller.rb#exec_command"
        ]
      ),
      build_entry.call(
        "minecraft.players.view",
        "查看在线玩家",
        execution_points: [
          "app/controllers/admin/minecraft/players_controller.rb#index"
        ]
      ),
      build_entry.call(
        "minecraft.players.manage",
        "管理 Minecraft 玩家缓存",
        execution_points: [
          "app/services/operations/minecraft_manual_tasks.rb"
        ]
      ),
      build_entry.call(
        "minecraft.primary_accounts.review",
        "审批 Minecraft 主账号切换",
        execution_points: [
          "app/controllers/admin/minecraft/primary_account_change_requests_controller.rb#update",
          "app/services/minecraft/decide_primary_account_change_request.rb#call"
        ]
      ),
      build_entry.call(
        "minecraft.primary_accounts.switch_for_user",
        "代用户切换 Minecraft 主账号",
        execution_points: [
          "app/controllers/admin/minecraft/primary_accounts_controller.rb#create",
          "app/services/minecraft/administrator_set_primary_account.rb#call"
        ]
      ),
      build_entry.call(
        "store.fulfillments.read",
        "View fulfillment recovery",
        admin_module: "store",
        execution_points: [
          "app/controllers/admin/store/fulfillments_controller.rb#index",
          "app/controllers/admin/store/fulfillments_controller.rb#show"
        ]
      ),
      build_entry.call(
        "store.fulfillments.retry",
        "Retry failed fulfillments",
        admin_module: "store",
        execution_points: [
          "app/controllers/admin/store/fulfillments_controller.rb#authorize_action",
          "app/controllers/admin/store/fulfillments_controller.rb#execute_action",
          "app/services/commerce/manual_fulfillment_action.rb"
        ]
      ),
      build_entry.call(
        "store.fulfillments.cancel",
        "Cancel pending fulfillments",
        admin_module: "store",
        execution_points: [
          "app/controllers/admin/store/fulfillments_controller.rb#authorize_action",
          "app/controllers/admin/store/fulfillments_controller.rb#execute_action",
          "app/services/commerce/manual_fulfillment_action.rb"
        ]
      ),
      build_entry.call(
        "minecraft.fulfillments.retry",
        "Legacy fulfillment retry permission",
        status: "reserved",
        admin_module: "store"
      ),
      build_entry.call(
        "system.bans.manage",
        "Manage access bans",
        execution_points: [
          "app/controllers/admin/system/ip_bans_controller.rb",
          "app/controllers/admin/system/email_bans_controller.rb"
        ]
      ),
      build_entry.call(
        "system.settings.manage",
        "管理系统设置",
        execution_points: [
          "app/controllers/admin/system/settings_controller.rb",
          "app/controllers/admin/system/feature_toggles_controller.rb",
          "app/controllers/admin/system/rate_limits_controller.rb"
        ]
      ),
      build_entry.call(
        "system.plugins.manage",
        "管理插件包",
        execution_points: [
          "app/controllers/admin/system/applications_controller.rb"
        ]
      ),
      build_entry.call(
        "system.plugins.view",
        "View plugins",
        execution_points: [
          "app/controllers/admin/system/applications_controller.rb#index"
        ]
      ),
      build_entry.call(
        "system.plugins.install",
        "Install and upgrade plugins",
        execution_points: [
          "app/controllers/admin/system/applications_controller.rb#install_plugin"
        ]
      ),
      build_entry.call(
        "system.plugins.enable",
        "Enable plugins",
        execution_points: [
          "app/controllers/admin/system/applications_controller.rb#enable_plugin"
        ]
      ),
      build_entry.call(
        "system.plugins.disable",
        "Disable plugins",
        execution_points: [
          "app/controllers/admin/system/applications_controller.rb#disable_plugin"
        ]
      ),
        build_entry.call(
          "system.plugins.diagnostics",
          "View plugin diagnostics",
          execution_points: [
            "app/controllers/admin/system/applications_controller.rb#index",
            "app/controllers/admin/system/applications_controller.rb#health_plugin",
            "app/controllers/admin/system/applications_controller.rb#reconcile_plugin_catalog"
          ]
        ),
      build_entry.call(
        "system.plugins.recover",
        "Recover plugins",
        execution_points: [
          "app/controllers/admin/system/applications_controller.rb#recover_plugin"
        ]
      ),
      build_entry.call(
        "system.plugins.rollback",
        "Roll back plugins",
        execution_points: [
          "app/controllers/admin/system/applications_controller.rb"
        ]
      ),
      build_entry.call(
        "system.plugins.uninstall_preserve",
        "Uninstall plugins and preserve data",
        execution_points: [
          "app/controllers/admin/system/applications_controller.rb#uninstall_plugin"
        ]
      ),
      build_entry.call(
        "system.plugins.uninstall_purge",
        "Uninstall plugins and purge data",
        execution_points: [
          "app/controllers/admin/system/applications_controller.rb#uninstall_plugin"
        ]
      ),
      build_entry.call(
        "system.plugins.settings.manage",
        "管理插件设置",
        execution_points: [
          "app/controllers/admin/system/plugin_settings_controller.rb"
        ]
      ),
      build_entry.call(
        "system.jobs.read",
        "查看后台任务",
        execution_points: [
          "app/controllers/admin/system/jobs_controller.rb#index",
          "app/services/operations/metrics/trend_query.rb#call",
          "app/constraints/sidekiq_web_constraint.rb"
        ]
      ),
      build_entry.call(
        "system.jobs.manage",
        "执行允许列表中的后台任务",
        execution_points: [
          "app/controllers/admin/system/jobs_controller.rb#run",
          "app/services/operations/enqueue_manual_task.rb#call"
        ]
      ),
      build_entry.call(
        "system.jobs.retry",
        "重试后台任务",
        status: "reserved",
        execution_points: []
      ),
      build_entry.call(
        "system.audit.read",
        "查看审计日志",
        execution_points: [
          "app/controllers/admin/audit_logs_controller.rb"
        ]
      ),
      build_entry.call(
        "system.audit.export",
        "导出审计日志",
        execution_points: [
          "app/controllers/admin/audit_logs_controller.rb#export"
        ]
      ),
      build_entry.call(
        "data_governance.read",
        "View data governance",
        admin_module: "system",
        execution_points: [
          "app/controllers/admin/system/data_governance_controller.rb#index"
        ]
      ),
      build_entry.call(
        "data_governance.policies.manage",
        "Manage retention policies",
        admin_module: "system",
        execution_points: [
          "app/controllers/admin/system/data_governance_controller.rb#update_policy",
          "app/services/data_governance/update_retention_policy.rb#call"
        ]
      ),
      build_entry.call(
        "data_governance.holds.manage",
        "Manage retention holds",
        admin_module: "system",
        execution_points: [
          "app/controllers/admin/system/data_governance_controller.rb#create_hold",
          "app/controllers/admin/system/data_governance_controller.rb#release_hold",
          "app/services/data_governance/place_retention_hold.rb#call",
          "app/services/data_governance/release_retention_hold.rb#call"
        ]
      ),
      build_entry.call(
        "data_governance.content.delete",
        "Soft-delete governed content",
        admin_module: "system",
        execution_points: [
          "app/controllers/admin/system/data_governance_controller.rb#soft_delete",
          "app/services/data_governance/soft_delete_content.rb#call"
        ]
      ),
      build_entry.call(
        "data_governance.content.restore",
        "Restore governed content",
        admin_module: "system",
        execution_points: [
          "app/controllers/admin/system/data_governance_controller.rb#restore",
          "app/services/data_governance/restore_content.rb#call"
        ]
      ),
      build_entry.call(
        "data_governance.content.purge",
        "Permanently purge governed content",
        admin_module: "system",
        execution_points: [
          "app/controllers/admin/system/data_governance_controller.rb#purge",
          "app/services/data_governance/permanently_purge_content.rb#call",
          "app/jobs/maintenance/purge_governed_content_job.rb#perform"
        ]
      ),
      build_entry.call(
        "admin.access",
        "访问后台",
        admin_module: nil,
        execution_points: [
          "app/controllers/admin/base_controller.rb#require_admin_access!"
        ]
      ),
      build_entry.call(
        "identity.groups.read",
        "View global identity groups",
        execution_points: [
          "app/controllers/admin/forum/user_groups_controller.rb#index",
          "app/controllers/admin/forum/user_groups_controller.rb#edit"
        ]
      ),
      build_entry.call(
        "identity.groups.manage",
        "Manage global identity groups",
        execution_points: [
          "app/controllers/admin/forum/user_groups_controller.rb#create",
          "app/controllers/admin/forum/user_groups_controller.rb#update",
          "app/controllers/admin/forum/user_groups_controller.rb#destroy"
        ]
      ),
      build_entry.call(
        "identity.groups.members.assign",
        "Assign global identity-group members",
        execution_points: [
          "app/services/identity/apply_group_mutation.rb",
          "app/controllers/admin/forum/user_groups_controller.rb#add_member",
          "app/controllers/admin/forum/user_groups_controller.rb#remove_member",
          "app/controllers/admin/forum/user_groups_controller.rb#set_primary"
        ]
      ),
      build_entry.call(
        "identity.groups.permissions.manage",
        "Manage global identity-group permissions",
        execution_points: [
          "app/services/identity/apply_group_mutation.rb",
          "app/controllers/admin/forum/user_groups_controller.rb#create",
          "app/controllers/admin/forum/user_groups_controller.rb#update"
        ]
      ),
      build_entry.call(
        "identity.roles.read",
        "View global roles",
        admin_module: "system",
        execution_points: [
          "app/controllers/admin/roles_controller.rb#index",
          "app/controllers/admin/roles_controller.rb#show"
        ]
      ),
      build_entry.call(
        "identity.roles.manage",
        "Manage global roles",
        admin_module: "system",
        execution_points: [
          "app/controllers/admin/roles_controller.rb#create",
          "app/controllers/admin/roles_controller.rb#update",
          "app/controllers/admin/roles_controller.rb#destroy"
        ]
      ),
      build_entry.call(
        "identity.permissions.explain",
        "Explain effective permissions",
        admin_module: "system",
        execution_points: [
          "app/controllers/admin/users_controller.rb#permission_explanation",
          "app/services/identity/permission_explanation.rb#call"
        ]
      )
    ].freeze

    INDEX = ENTRIES.index_by(&:key).freeze
    ACTIVE_ENTRIES = ENTRIES.select(&:active?).freeze
    ACTIVE_KEYS = ACTIVE_ENTRIES.map(&:key).freeze

    class << self
      def entries
        ENTRIES
      end

      def active_entries
        ACTIVE_ENTRIES
      end

      alias_method :assignable_entries, :active_entries

      def active_keys
        ACTIVE_KEYS
      end

      def assignable_keys
        (ACTIVE_KEYS + plugin_permission_contributions.map { |entry| entry.fetch(:id).to_s }).uniq.sort.freeze
      end

      def active_key?(key)
        INDEX[key.to_s]&.active? || false
      end

      def assignable_key?(key)
        assignable_keys.include?(key.to_s)
      end

      def find(key)
        INDEX[key.to_s]
      end

      def fetch(key)
        INDEX.fetch(key.to_s)
      end

      def grouped_json(locale: I18n.locale)
        core_groups = active_entries
          .group_by(&:category)
          .sort
          .map do |domain, domain_entries|
            {
              key: domain,
              name: I18n.t(
                "mcweb.permission_domains.#{domain}",
                locale:,
                default: domain.humanize
              ),
              permissions: domain_entries.sort_by(&:key).map do |entry|
                {
                  key: entry.key,
                  name: localized_value(entry, :name, locale:),
                  description: localized_value(entry, :description, locale:)
                }
              end
            }
          end
        core_groups + plugin_groups(locale:)
      end

      def seed_attributes(locale: :en)
        active_entries.map do |entry|
          {
            key: entry.key,
            name: localized_value(entry, :name, locale:),
            description: localized_value(entry, :description, locale:),
            category: entry.category
          }
        end
      end

      private

      def plugin_permission_contributions
        return [] unless defined?(Mcweb::Plugins)
        return [] unless Mcweb::Plugins.respond_to?(:permission_contributions)

        Array(Mcweb::Plugins.permission_contributions)
          .map(&:symbolize_keys)
          .reject { |entry| INDEX.key?(entry.fetch(:id).to_s) }
      rescue StandardError => error
        Rails.logger.warn(
          "[identity.permission_catalog] plugin permission catalog unavailable: " \
          "#{error.class}: #{error.message}"
        )
        []
      end

      def plugin_groups(locale:)
        plugin_permission_contributions
          .group_by { |entry| entry.fetch(:group).to_s }
          .sort
          .map do |group, entries|
            {
              key: "plugin:#{group}",
              name: group.tr("._", " ").humanize,
              permissions: entries.sort_by { |entry| entry.fetch(:id).to_s }.map do |entry|
                {
                  key: entry.fetch(:id).to_s,
                  name: localized_phrase(entry.fetch(:title_phrase), locale:),
                  description: localized_phrase(entry.fetch(:description_phrase), locale:)
                }
              end
            }
          end
      end

      def localized_phrase(key, locale:)
        phrase_key = key.to_s
        return I18n.t(phrase_key, locale:) if I18n.exists?(phrase_key, locale)

        phrase_key
      end

      def localized_value(entry, attribute, locale:)
        key = "#{entry.i18n_key}.#{attribute}"
        return I18n.t(key, locale:) if I18n.exists?(key, locale)

        attribute == :name ? entry.fallback_name : entry.fallback_description
      end
    end
  end
end
