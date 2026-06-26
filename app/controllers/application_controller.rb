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

  allow_browser versions: :modern

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
      share[:notifications] = {
        unread_count: current_user.notifications.unread.count,
        url: forum_notifications_path
      }
      share[:forum_unread] = {
        count: Community::ReadState.with_unread_for(current_user).count,
        url: forum_unread_path
      }
      share[:forum_new] = {
        count: Community::Topic.unseen_for(current_user).count,
        url: forum_new_feed_path
      }
      assigned_count = Community::Topic.published_listed.where(assigned_to: current_user).count
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
    end

    if FeatureFlags.enabled?(:forum)
      announcements = Community::Topic.global_announcements.order(last_posted_at: :desc).limit(3)
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

    share = share.merge(share_active_template)
    share[:csrf_token] = form_authenticity_token
    share
  end

  def safe_local_path(path)
    safe_local_redirect_path(path, fallback: nil)
  end
end
