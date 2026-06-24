# frozen_string_literal: true

module Admin
  module Forum
    class BadgesController < BaseController
      before_action -> { require_permission("forum.badges.manage") }
      before_action :set_badge, only: %i[edit update destroy]

      def index
        badges = Community::Badge.order(:name)

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("badges.title"),
          columns: [
            { key: "name", label: t("mcweb.admin.forum.col_name"), link: true },
            { key: "slug", label: t("mcweb.admin.forum.col_slug") },
            { key: "grant_rule", label: forum_t("badges.col_grant_rule") },
            { key: "users_count", label: forum_t("badges.col_users_count") }
          ],
          rows: badges.map do |badge|
            {
              id: badge.id,
              name: "#{badge.icon} #{badge.name}",
              slug: badge.slug,
              grant_rule: grant_rule_label(badge.grant_rule),
              users_count: badge.user_badges.count.to_s,
              url: edit_admin_forum_badge_path(badge)
            }
          end,
          actions: [ { label: forum_t("badges.action_new"), href: new_admin_forum_badge_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/Badges/Form", props: form_props(Community::Badge.new)
      end

      def edit
        render inertia: "Admin/Forum/Badges/Form", props: form_props(@badge)
      end

      def create
        badge = Community::Badge.new(badge_params)
        if badge.save
          redirect_to admin_forum_badges_path, notice: t("mcweb.flash.created", resource: t("mcweb.resources.badge"))
        else
          render inertia: "Admin/Forum/Badges/Form", props: form_props(badge), status: :unprocessable_entity
        end
      end

      def update
        if @badge.update(badge_params)
          redirect_to admin_forum_badges_path, notice: t("mcweb.flash.updated", resource: t("mcweb.resources.badge"))
        else
          render inertia: "Admin/Forum/Badges/Form", props: form_props(@badge), status: :unprocessable_entity
        end
      end

      def destroy
        @badge.destroy!
        redirect_to admin_forum_badges_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.badge"))
      end

      private

      def set_badge
        @badge = Community::Badge.find(params[:id])
      end

      def badge_params
        params.require(:badge).permit(:name, :slug, :description, :icon, :color, :grant_rule, :grant_threshold, :tier)
      end

      def form_props(badge)
        {
          title: badge.persisted? ? forum_t("badges.form_edit") : forum_t("badges.form_new"),
          badge: {
            id: badge.id,
            name: badge.name || "",
            slug: badge.slug || "",
            description: badge.description || "",
            icon: badge.icon || "🏅",
            color: badge.color || "#6366f1",
            grant_rule: badge.grant_rule || "manual",
            grant_threshold: badge.grant_threshold || 0,
            tier: badge.tier || "bronze"
          },
          submitUrl: badge.persisted? ? admin_forum_badge_path(badge) : admin_forum_badges_path,
          method: badge.persisted? ? "patch" : "post",
          backUrl: admin_forum_badges_path
        }
      end
    end
  end
end
