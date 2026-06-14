# frozen_string_literal: true

module Admin
  module Forum
    class BadgesController < BaseController
      before_action -> { require_permission("forum.badges.manage") }
      before_action :set_badge, only: %i[destroy]

      def index
        badges = Community::Badge.order(:name)

        render inertia: "Admin/Generic/Index", props: {
          title: "论坛徽章",
          columns: [
            { key: "name", label: "名称" },
            { key: "slug", label: "标识" },
            { key: "grant_rule", label: "授予规则" },
            { key: "users_count", label: "用户数" }
          ],
          rows: badges.map do |badge|
            {
              id: badge.id,
              name: "#{badge.icon} #{badge.name}",
              slug: badge.slug,
              grant_rule: badge.grant_rule,
              users_count: badge.user_badges.count
            }
          end,
          newPath: nil
        }
      end

      def create
        badge = Community::Badge.new(badge_params)
        if badge.save
          redirect_to admin_forum_badges_path, notice: "徽章已创建。"
        else
          redirect_to admin_forum_badges_path, alert: badge.errors.full_messages.join(", ")
        end
      end

      def destroy
        @badge.destroy!
        redirect_to admin_forum_badges_path, notice: "徽章已删除。"
      end

      private

      def set_badge
        @badge = Community::Badge.find(params[:id])
      end

      def badge_params
        params.require(:badge).permit(:name, :slug, :description, :icon, :color, :grant_rule, :grant_threshold)
      end
    end
  end
end
