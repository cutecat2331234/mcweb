# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style forum theme management (color tokens applied to the portal).
    class ThemesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_theme, only: %i[edit update destroy]

      def index
        themes = ::Community::ForumTheme.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("themes.title"),
          subtitle: forum_t("themes.description"),
          columns: [
            admin_column(:name, forum_t("themes.col_name"), link: true),
            admin_column(:is_default, forum_t("themes.col_default")),
            admin_column(:active, forum_t("themes.col_active"))
          ],
          rows: themes.map do |theme|
            admin_row(
              name: theme.name,
              is_default: forum_yes_no(theme.is_default),
              active: forum_yes_no(theme.active),
              url: edit_admin_forum_theme_path(theme)
            )
          end,
          actions: [ { label: forum_t("themes.action_new"), href: new_admin_forum_theme_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/Themes/Form", props: form_props(::Community::ForumTheme.new)
      end

      def create
        theme = ::Community::ForumTheme.new(theme_params)
        if theme.save
          enforce_single_default(theme)
          redirect_to admin_forum_themes_path, notice: t("mcweb.flash.forum_theme_created")
        else
          render inertia: "Admin/Forum/Themes/Form", props: form_props(theme), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/Themes/Form", props: form_props(@theme, editing: true)
      end

      def update
        if @theme.update(theme_params)
          enforce_single_default(@theme)
          redirect_to admin_forum_themes_path, notice: t("mcweb.flash.forum_theme_updated")
        else
          render inertia: "Admin/Forum/Themes/Form", props: form_props(@theme, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @theme.destroy!
        redirect_to admin_forum_themes_path, notice: t("mcweb.flash.forum_theme_deleted")
      end

      private

      def set_theme
        @theme = ::Community::ForumTheme.find(params[:id])
      end

      def theme_params
        params.require(:forum_theme).permit(:name, :primary_color, :accent_color, :is_default, :active)
      end

      # Keep at most one default theme.
      def enforce_single_default(theme)
        return unless theme.is_default?

        ::Community::ForumTheme.where.not(id: theme.id).where(is_default: true).update_all(is_default: false)
        ::Community::ForumTheme.clear_cache!
      end

      def form_props(theme, editing: false)
        {
          title: editing ? forum_t("themes.form_edit") : forum_t("themes.form_new"),
          forum_theme: {
            name: theme.name || "",
            primary_color: theme.primary_color || "",
            accent_color: theme.accent_color || "",
            is_default: theme.is_default.nil? ? false : theme.is_default,
            active: theme.active.nil? ? true : theme.active
          },
          submitUrl: editing ? admin_forum_theme_path(theme) : admin_forum_themes_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_themes_path,
          deleteUrl: editing ? admin_forum_theme_path(theme) : nil
        }
      end
    end
  end
end
