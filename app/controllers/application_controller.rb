class ApplicationController < ActionController::Base
  include Authentication
  include InstallationGuard
  include ServiceResponder
  include Pagy::Backend
  include InertiaSerializable
  include BlockedUsersFilterable
  include TouchLastSeen

  allow_browser versions: :modern

  stale_when_importmap_changes

  inertia_config layout: "inertia"

  inertia_share do
    share = {
      auth: {
        user: inertia_user
      },
      flash: {
        notice: flash[:notice],
        alert: flash[:alert]
      }
    }

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

    if logged_in?
      share[:notifications] = {
        unread_count: current_user.notifications.unread.count,
        url: forum_notifications_path
      }
      share[:forum_unread] = {
        count: Community::ReadState.with_unread_for(current_user).count,
        url: forum_unread_path
      }
      assigned_count = Community::Topic.published_listed.where(assigned_to: current_user).count
      if assigned_count.positive? || current_user.permission?("forum.topics.lock")
        share[:forum_assigned] = {
          count: assigned_count,
          url: forum_assigned_path
        }
      end
      share[:messages_unread] = {
        count: Community::Conversation.for_user(current_user).sum { |c| c.unread_count_for(current_user) },
        url: forum_conversations_path
      }
    end

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

    share
  end
end
