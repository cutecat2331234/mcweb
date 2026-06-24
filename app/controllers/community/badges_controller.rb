# frozen_string_literal: true

module Community
  class BadgesController < ApplicationController
    def index
      badges = Community::Badge.order(:name)
      user_counts = Community::UserBadge.where(forum_badge_id: badges.map(&:id)).group(:forum_badge_id).count

      render inertia: "Community/Badges/Index", props: {
        badges: badges.map { |badge| serialize_badge_summary(badge, users_count: user_counts[badge.id].to_i) }
      }
    end

    def show
      badge = Community::Badge.find_by!(slug: params[:id])
      @pagy, user_badges = pagy(:offset,
        badge.user_badges.includes(:user).order(granted_at: :desc),
        limit: 30
      )

      render inertia: "Community/Badges/Show", props: {
        badge: serialize_badge_summary(badge, users_count: badge.user_badges.count),
        holders: user_badges.map do |ub|
          {
            username: ub.user.username,
            display_name: ub.user.display_name,
            avatar_url: ub.user.avatar_url,
            profile_url: forum_user_path(ub.user.username),
            granted_at: l(ub.granted_at, format: :short)
          }
        end,
        pagination: pagy_props(@pagy)
      }
    end

    private

    def serialize_badge_summary(badge, users_count:)
      {
        name: badge.name,
        slug: badge.slug,
        icon: badge.icon,
        color: badge.color,
        description: badge.description,
        grant_rule: badge.grant_rule,
        grant_rule_label: grant_rule_label(badge),
        tier: badge.tier,
        grouping: badge.grouping,
        users_count: users_count,
        url: forum_badge_path(badge.slug)
      }
    end

    def grant_rule_label(badge)
      base = I18n.t("mcweb.forum.badges.#{badge.grant_rule}", default: badge.grant_rule)
      if badge.grant_rule.in?(%w[posts_count likes_received]) && badge.grant_threshold.positive?
        "#{base}（#{badge.grant_threshold}）"
      else
        base
      end
    end
  end
end
