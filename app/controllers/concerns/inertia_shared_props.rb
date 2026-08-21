# frozen_string_literal: true

module InertiaSharedProps
  extend ActiveSupport::Concern

  private

  def build_inertia_shared_props
    share = {
      locale: I18n.locale.to_s,
      available_locales: I18n.available_locales.map(&:to_s),
      auth: { user: inertia_user },
      flash: {
        notice: flash[:notice],
        alert: flash[:alert],
        message_edit_succeeded: flash[:message_edit_succeeded],
        post_edit_succeeded: flash[:post_edit_succeeded],
        profile_wall_edit_succeeded: flash[:profile_wall_edit_succeeded]
      },
      developer_mode: developer_mode_frontend_payload,
      admin_demo_enabled: admin_demo_enabled?,
      features: FeatureFlags.frontend_hash
    }

    append_store_shared_props(share) if store_shared_props_required?
    if logged_in? && FeatureFlags.enabled?(:forum)
      share[:staff_workspace] = InertiaRails.defer(
        group: "portal_navigation",
        rescue: true
      ) { staff_workspace_navigation_payload }
    end
    append_forum_shared_props(share) if inertia_feature_domain == :forum
    append_minecraft_shared_props(share) if inertia_feature_domain == :minecraft
    append_website_shared_props(share) if inertia_feature_domain == :website
    append_plugin_shared_props(share)

    share.merge!(share_active_template)
    share[:csrf_token] = form_authenticity_token
    share
  end

  def staff_workspace_navigation_payload
    policy = Community::ModerationWorkbench::Policy.new(current_user)
    return unless policy.accessible?

    active_count = policy.visible_scope
      .where(status: Community::ModerationCase::ACTIVE_STATUSES)
      .count
    {
      count: active_count,
      url: staff_root_path,
      queue_url: staff_moderation_cases_path
    }
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  def inertia_feature_domain
    @inertia_feature_domain ||= begin
      path = controller_path.to_s
      case path
      when %r{\Aadmin/store(?:/|\z)} then :admin_store
      when %r{\Aadmin(?:/|\z)} then :admin
      when %r{\Awebsite(?:/|\z)} then :website
      when %r{\Acommunity(?:/|\z)} then :forum
      when %r{\Acommerce(?:/|\z)}, %r{\Apayments(?:/|\z)} then :commerce
      when %r{\Aminecraft(?:/|\z)} then :minecraft
      when %r{\Aidentity(?:/|\z)} then :identity
      when %r{\Aee/chat(?:/|\z)}, %r{\Aee/direct_messages(?:/|\z)} then :chat
      else :core
      end
    end
  end

  def store_shared_props_required?
    FeatureFlags.enabled?(:store) &&
      inertia_feature_domain.in?(%i[commerce admin_store])
  end

  def append_store_shared_props(share)
    share[:storeFeatures] = Commerce::StoreFeatures.frontend_hash
    if controller_path.start_with?("admin/store/products")
      image_packs = Mcweb::ImagePackRegistry.frontend_hash
      share[:imagePacks] = image_packs if image_packs.present?
    end
    return unless inertia_feature_domain == :commerce

    share[:cart] = InertiaRails.defer(group: "portal_navigation", rescue: true) do
      cart_navigation_payload
    end
  end

  def cart_navigation_payload
    cart = if logged_in?
      Commerce::Cart.find_by(user: current_user)
    else
      token = cookies.signed[:cart_token]
      Commerce::Cart.find_by(session_token: token) if token.present?
    end
    return unless cart

    {
      count: cart.items.sum(:quantity),
      url: store_cart_path
    }
  end

  def append_forum_shared_props(share)
    if logged_in?
      %i[
        notifications
        forum_unread
        forum_new
        forum_assigned
        forum_moderation_pending
        messages_unread
        forum_check_in
      ].each do |key|
        share[key] = InertiaRails.defer(
          group: "portal_navigation",
          rescue: true
        ) { forum_navigation_state[key] }
      end
    end

    append_forum_announcements(share)

    forum_theme_tokens = Community::ForumTheme.active_tokens
    share[:forum_theme] = forum_theme_tokens if forum_theme_tokens.present?

    overrides = unflatten_phrase_overrides(
      Community::PhraseOverride.map[I18n.locale.to_s]
    )
    share[:phrase_overrides] = overrides if overrides.present?

    nav_pages = Community::ForumPage.nav_items
    share[:forum_nav_pages] = nav_pages if nav_pages.present?
    append_forum_notices(share)
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  def forum_navigation_state
    @forum_navigation_state ||= begin
      visible_section_ids = Community::SectionAccess.visible_ids(user: current_user)
      assigned_count = Community::ForumAccess.topic_scope(
        relation: Community::Topic.published_listed.where(assigned_to: current_user),
        user: current_user
      ).count
      checkin_today = Community::CheckIn.find_by(
        user: current_user,
        checked_on: Date.current
      )
      last_checkin = checkin_today || Community::CheckIn
        .where(user: current_user)
        .order(checked_on: :desc)
        .first
      checked_today = checkin_today.present?
      current_streak = if checked_today
        checkin_today.streak
      elsif last_checkin && last_checkin.checked_on == Date.current - 1
        last_checkin.streak
      else
        0
      end

      {
        notifications: {
          unread_count: current_user.notifications.unread.count,
          url: forum_notifications_path
        },
        forum_unread: {
          count: Community::ReadState
            .with_unread_for(current_user)
            .where(forum_topics: { forum_section_id: visible_section_ids })
            .count,
          url: forum_unread_path
        },
        forum_new: {
          count: Community::ForumAccess
            .topic_scope(
              relation: Community::Topic.unseen_for(current_user),
              user: current_user
            )
            .count,
          url: forum_new_feed_path
        },
        forum_assigned: if assigned_count.positive? ||
            current_user.permission?("forum.topics.lock")
          { count: assigned_count, url: forum_assigned_path }
                        end,
        forum_moderation_pending: if
          Community::SectionModeration.staff_for_any_section?(current_user)
          {
            count: Community::SectionModeration
              .pending_posts_scope_for(current_user)
              .count,
            url: forum_moderation_approvals_path
          }
                                  end,
        messages_unread: {
          count: Community::Conversation.total_unread_count_for(current_user),
          url: forum_conversations_path
        },
        forum_check_in: {
          checked_today: checked_today,
          streak: current_streak,
          url: forum_check_in_path
        }
      }
    end
  end

  def append_forum_announcements(share)
    announcements = Community::ForumAccess.listed_topic_scope(
      relation: Community::Topic.global_announcements,
      user: current_user
    ).order(last_posted_at: :desc).limit(3).to_a
    if logged_in?
      dismissed = Array(current_user.dismissed_global_announcement_ids).map(&:to_s)
      announcements.reject! { |topic| dismissed.include?(topic.public_id) }
    end
    return if announcements.empty?

    share[:global_announcements] = announcements.map do |topic|
      {
        title: topic.title,
        url: forum_topic_path(topic),
        id: topic.public_id
      }
    end
  end

  def append_forum_notices(share)
    notices = Community::Notice.active.ordered.to_a
      .select { |notice| notice.visible_to?(current_user) }
    if logged_in?
      dismissed = Array(current_user.dismissed_forum_notice_ids).map(&:to_s)
      notices.reject! { |notice| dismissed.include?(notice.id.to_s) }
    end
    return if notices.empty?

    share[:forum_notices] = notices.map do |notice|
      formatted = Community::FormatPostBody.call(body: notice.message)
      {
        id: notice.id,
        title: notice.title,
        message_html: formatted.success? ?
          formatted.value : ERB::Util.html_escape(notice.message),
        style: notice.style,
        dismissible: notice.dismissible,
        dismiss_url: forum_dismiss_notice_path(notice)
      }
    end
  end

  def append_minecraft_shared_props(share)
    return unless FeatureFlags.enabled?(:minecraft)

    servers = Minecraft::Server.online_servers.limit(5).to_a
    return if servers.empty?

    latest_snapshots = Minecraft::ServerSnapshot
      .where(minecraft_server_id: servers.map(&:id))
      .order(created_at: :desc)
      .each_with_object({}) do |snapshot, result|
        result[snapshot.minecraft_server_id] ||= snapshot
      end
    stale_nodes = Minecraft::Node.where(status: :online)
      .where("last_heartbeat_at IS NULL OR last_heartbeat_at < ?", 3.minutes.ago)
      .count
    mismatched = Minecraft::Server.managed_by_node
      .where("metadata ? 'process_mismatch_alert'")
      .count
    maintenance_count = Minecraft::Server.where(status: :maintenance).count +
      Minecraft::Node.where(status: :maintenance).count

    share[:minecraft_servers] = servers.map do |server|
      snapshot = latest_snapshots[server.id]
      {
        name: server.name,
        online: snapshot&.online_players.to_i,
        max: snapshot&.max_players.to_i,
        status: server.status,
        anomaly: server.metadata.key?("process_mismatch_alert") ||
          server.status == "maintenance"
      }
    end
    share[:minecraft_health] = {
      stale_nodes: stale_nodes,
      process_mismatch: mismatched,
      maintenance: maintenance_count,
      alert: stale_nodes.positive? || mismatched.positive? ||
        maintenance_count.positive?
    }
  end

  def append_website_shared_props(share)
    nav_items = Website::NavItem.frontend_items("header")
    share[:website_nav] = nav_items if nav_items.present?
  rescue ActiveRecord::StatementInvalid, NameError
    nil
  end

  def append_plugin_shared_props(share)
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
    return if plugin_phrases.empty?

    plugin_overrides = unflatten_phrase_overrides(plugin_phrases)
    share[:phrase_overrides] = (share[:phrase_overrides] || {})
      .deep_merge(plugin_overrides)
  rescue StandardError => error
    Rails.logger.warn(
      "[mcweb.plugins] contribution presentation skipped: " \
      "#{error.class}: #{error.message}"
    )
  end
end
