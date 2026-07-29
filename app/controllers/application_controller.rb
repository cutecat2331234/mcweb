class ApplicationController < ActionController::Base
  include Authentication
  include CsrfCookie
  include InstallationGuard
  include FeatureGuard
  include ServiceResponder
  include Pagy::Method
  include InertiaSerializable
  include BlockedUsersFilterable
  include TouchLastSeen
  include FrontendTemplateShare
  include LocaleSettable

  before_action :require_totp_setup
  before_action :audit_developer_mode_configuration
  before_action :enforce_plugin_maintenance_window
  before_action :reconcile_plugin_runtime_generation
  after_action :mark_developer_mode_response

  allow_browser versions: :modern,
    unless: -> { Mcweb::DeveloperMode.allow?(:skip_browser_policy) }

  stale_when_importmap_changes

  inertia_config layout: "inertia"

  inertia_share do
    share = {
      locale: I18n.locale.to_s,
      available_locales: I18n.available_locales.map(&:to_s),
      auth: {
        user: inertia_user
      },
      flash: {
        notice: flash[:notice],
        alert: flash[:alert]
      },
      developer_mode: developer_mode_frontend_payload,
      admin_demo_enabled: admin_demo_enabled?,
      features: FeatureFlags.frontend_hash
    }

    if FeatureFlags.enabled?(:store)
      share[:storeFeatures] = Commerce::StoreFeatures.frontend_hash
      image_packs = Mcweb::ImagePackRegistry.frontend_hash
      share[:imagePacks] = image_packs if image_packs.present?

      cart = if logged_in?
               Commerce::Cart.find_by(user: current_user)
      else
               token = cookies.signed[:cart_token]
               Commerce::Cart.find_by(session_token: token) if token.present?
      end

      if cart
        share[:cart] = {
          count: cart.items.sum(:quantity),
          url: store_cart_path
        }
      end
    end

    if FeatureFlags.enabled?(:forum) && logged_in?
      visible_section_ids = Community::SectionAccess.visible_ids(user: current_user)
      share[:notifications] = {
        unread_count: current_user.notifications.unread.count,
        url: forum_notifications_path
      }
      share[:forum_unread] = {
        count: Community::ReadState
          .with_unread_for(current_user)
          .where(forum_topics: { forum_section_id: visible_section_ids })
          .count,
        url: forum_unread_path
      }
      share[:forum_new] = {
        count: Community::ForumAccess
          .topic_scope(relation: Community::Topic.unseen_for(current_user), user: current_user)
          .count,
        url: forum_new_feed_path
      }
      assigned_count = Community::ForumAccess.topic_scope(
        relation: Community::Topic.published_listed.where(assigned_to: current_user),
        user: current_user
      ).count
      if assigned_count.positive? || current_user.permission?("forum.topics.lock")
        share[:forum_assigned] = {
          count: assigned_count,
          url: forum_assigned_path
        }
      end
      if Community::SectionModeration.staff_for_any_section?(current_user)
        pending_count = Community::SectionModeration.pending_posts_scope_for(current_user).count
        share[:forum_moderation_pending] = {
          count: pending_count,
          url: forum_moderation_approvals_path
        }
      end
      share[:messages_unread] = {
        count: Community::Conversation.total_unread_count_for(current_user),
        url: forum_conversations_path
      }

      checkin_today = Community::CheckIn.find_by(user: current_user, checked_on: Date.current)
      last_checkin = checkin_today || Community::CheckIn.where(user: current_user).order(checked_on: :desc).first
      checked_today = checkin_today.present?
      # The running streak: today's value if already checked in, otherwise the
      # last check-in's streak only while it is still "alive" (was yesterday).
      current_streak = if checked_today
                         checkin_today.streak
      elsif last_checkin && last_checkin.checked_on == Date.current - 1
                         last_checkin.streak
      else
                         0
      end
      share[:forum_check_in] = {
        checked_today: checked_today,
        streak: current_streak,
        url: forum_check_in_path
      }
    end

    if FeatureFlags.enabled?(:forum)
      announcements = Community::ForumAccess.listed_topic_scope(
        relation: Community::Topic.global_announcements,
        user: current_user
      ).order(last_posted_at: :desc).limit(3)
      if logged_in?
        dismissed = Array(current_user.dismissed_global_announcement_ids).map(&:to_s)
        announcements = announcements.reject { |topic| dismissed.include?(topic.public_id) }
      end
      if announcements.any?
        share[:global_announcements] = announcements.map do |topic|
          {
            title: topic.title,
            url: forum_topic_path(topic),
            id: topic.public_id
          }
        end
      end

      forum_theme_tokens = Community::ForumTheme.active_tokens
      share[:forum_theme] = forum_theme_tokens if forum_theme_tokens.present?

      begin
        overrides = unflatten_phrase_overrides(Community::PhraseOverride.map[I18n.locale.to_s])
        share[:phrase_overrides] = overrides if overrides.present?
      rescue StandardError
        nil
      end

      nav_pages = Community::ForumPage.nav_items
      share[:forum_nav_pages] = nav_pages if nav_pages.present?

      notices = Community::Notice.active.ordered.select { |notice| notice.visible_to?(current_user) }
      if logged_in?
        dismissed_notices = Array(current_user.dismissed_forum_notice_ids).map(&:to_s)
        notices = notices.reject { |notice| dismissed_notices.include?(notice.id.to_s) }
      end
      if notices.any?
        share[:forum_notices] = notices.map do |notice|
          formatted = Community::FormatPostBody.call(body: notice.message)
          {
            id: notice.id,
            title: notice.title,
            message_html: formatted.success? ? formatted.value : ERB::Util.html_escape(notice.message),
            style: notice.style,
            dismissible: notice.dismissible,
            dismiss_url: forum_dismiss_notice_path(notice)
          }
        end
      end
    end

    if FeatureFlags.enabled?(:minecraft)
      servers = Minecraft::Server.online_servers.limit(5)
      stale_nodes = Minecraft::Node.where(status: :online)
        .where("last_heartbeat_at IS NULL OR last_heartbeat_at < ?", 3.minutes.ago).count
      mismatched = Minecraft::Server.managed_by_node.where("metadata ? 'process_mismatch_alert'").count
      maintenance_count = Minecraft::Server.where(status: :maintenance).count +
        Minecraft::Node.where(status: :maintenance).count
      if servers.any?
        share[:minecraft_servers] = servers.map do |server|
          snapshot = server.server_snapshots.order(created_at: :desc).first
          {
            name: server.name,
            online: snapshot&.online_players.to_i,
            max: snapshot&.max_players.to_i,
            status: server.status,
            anomaly: server.metadata.key?("process_mismatch_alert") || server.status == "maintenance"
          }
        end
        share[:minecraft_health] = {
          stale_nodes: stale_nodes,
          process_mismatch: mismatched,
          maintenance: maintenance_count,
          alert: stale_nodes.positive? || mismatched.positive? || maintenance_count.positive?
        }
      end
    end

    begin
      nav_items = Website::NavItem.visible_items.for_location("header").ordered
      if nav_items.any?
        share[:website_nav] = nav_items.map { |item| { label: item.label, href: item.href } }
      end
    rescue ActiveRecord::StatementInvalid, NameError
      nil
    end

    begin
      plugin_presenter = PluginContributionPresenter.new(
        user: current_user,
        locale: I18n.locale,
        path: request.path
      )
      plugin_payload = plugin_presenter.shared_payload
      if plugin_payload.dig(:navigation, :public).any? ||
          plugin_payload.dig(:navigation, :admin).any? ||
          plugin_payload[:ui_slots].any?
        share[:plugin_contributions] = plugin_payload
      end

      plugin_phrases = plugin_presenter.translation_overrides
      if plugin_phrases.any?
        plugin_overrides = unflatten_phrase_overrides(plugin_phrases)
        share[:phrase_overrides] = (share[:phrase_overrides] || {}).deep_merge(plugin_overrides)
      end
    rescue StandardError => e
      Rails.logger.warn(
        "[mcweb.plugins] contribution presentation skipped: #{e.class}"
      )
    end

    share = share.merge(share_active_template)
    share[:csrf_token] = form_authenticity_token
    share
  end

  private

  def audit_developer_mode_configuration
    Operations::AuditDeveloperModeConfiguration.call
  end

  def enforce_plugin_maintenance_window
    return unless defined?(PluginMaintenanceWindow)
    return if controller_path.start_with?("admin/", "setup/", "api/")
    return if controller_path == "identity/sessions"
    return if %w[health commerce/webhooks].include?(controller_path)
    return if current_user&.can_access_admin?
    return unless PluginMaintenanceWindow.active?

    response.set_header("Retry-After", "30")
    payload = {
      error: "plugin_maintenance",
      message: t("mcweb.plugin_maintenance.message")
    }
    if request.format.json?
      render json: payload, status: :service_unavailable
    else
      render(
        template: "shared/plugin_maintenance",
        layout: false,
        status: :service_unavailable,
        locals: payload
      )
    end
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  def reconcile_plugin_runtime_generation
    Mcweb::Plugins.generation_coordinator.reconcile_current_process!(process_kind: "web")
  rescue StandardError => e
    Rails.logger.warn(
      "[mcweb.plugins] generation reconciliation skipped: #{e.class}: #{e.message}"
    )
  end

  def safe_local_path(path)
    safe_local_redirect_path(path, fallback: nil)
  end

  private

  def admin_demo_enabled?
    Mcweb::DeveloperMode.enabled?
  end

  def developer_mode_frontend_payload
    return { enabled: false } unless Mcweb::DeveloperMode.enabled?

    payload = {
      enabled: true,
      profile: Mcweb::DeveloperMode.profile,
      production_environment: Rails.env.production?,
      environment: Rails.env,
      request_id: request.request_id,
      workbench_access:
        current_user.present? &&
          current_user.can_access_admin? &&
          current_user.permission?("admin.access") &&
          current_user.permission?("system.settings.manage")
    }

    tools_access =
      current_user.present? &&
        (
          current_user.developer_mode_persona.present? ||
          current_user.permission?("system.settings.manage")
        )
    payload[:tools_access] = tools_access
    return payload unless tools_access

    available_personas = User
      .where(
        developer_mode_persona: User::DEVELOPER_MODE_PERSONAS,
        status: "active"
      )
      .pluck(:developer_mode_persona)
    payload.merge(
      current_persona:
        current_user.developer_mode_persona.presence || "operator",
      persona_switch_url: developer_mode_switch_persona_path,
      personas: User::DEVELOPER_MODE_PERSONAS.map do |persona|
        {
          key: persona,
          available: available_personas.include?(persona)
        }
      end
    )
  rescue ActiveRecord::ActiveRecordError
    payload
  end

  def mark_developer_mode_response
    return unless Mcweb::DeveloperMode.enabled?

    response.set_header("X-McWeb-Developer-Mode", "unrestricted")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    existing_cache_control = response.get_header("Cache-Control").to_s
    response.set_header(
      "Cache-Control",
      existing_cache_control.match?(/(?:^|,)\s*private(?:\s*,|$)/i) ? "private, no-store" : "no-store"
    )
  end

  # Turns a flat map of dotted i18n keys into a nested hash so vue-i18n can
  # merge it as locale messages. { "forum.top.title" => "x" } becomes
  # { "forum" => { "top" => { "title" => "x" } } }.
  def unflatten_phrase_overrides(flat)
    nested = {}
    Array(flat).each do |key, value|
      segments = key.to_s.split(".")
      next if segments.empty?

      cursor = nested
      segments[0...-1].each do |segment|
        existing = cursor[segment]
        cursor = (existing.is_a?(Hash) ? existing : (cursor[segment] = {}))
      end
      cursor[segments[-1]] = value
    end
    nested
  end
end
