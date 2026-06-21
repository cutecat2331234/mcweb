# frozen_string_literal: true

module Admin
  module Website
    class ThemesController < BaseController
      before_action -> { require_permission("website.pages.read") }, only: %i[index show]
      before_action -> { require_permission("website.pages.edit") }, except: %i[index show activate]
      before_action -> { require_permission("website.pages.publish") }, only: %i[activate]
      before_action :set_theme, only: %i[show edit update destroy activate]

      def index
        themes = ::Website::Theme.order(:name)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.website.themes.title", default: "Website themes"),
          columns: [
            admin_column(:name, t("admin.common.title"), link: true),
            admin_column(:key, "Key"),
            admin_column(:active, t("admin.common.status"))
          ],
          rows: themes.map do |theme|
            admin_row(
              name: theme.name,
              key: theme.key,
              active: theme.active? ? t("admin.common.yes", default: "Yes") : "—",
              url: admin_website_theme_path(theme)
            )
          end,
          actions: [ { label: t("mcweb.admin.website.themes.new", default: "New theme"), href: new_admin_website_theme_path } ]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @theme.name,
          subtitle: @theme.key,
          fields: [
            { label: t("admin.common.status"), value: @theme.active? ? "active" : "inactive" },
            { label: "Tokens", value: @theme.tokens.to_json.truncate(200) }
          ],
          backUrl: admin_website_themes_path,
          actions: [
            { label: t("mcweb.admin.ui.edit"), href: edit_admin_website_theme_path(@theme) },
            (@theme.active? ? nil : { label: t("mcweb.admin.website.themes.activate", default: "Activate"), href: activate_admin_website_theme_path(@theme), method: "post" })
          ].compact
        }
      end

      def new
        render inertia: "Admin/Website/Themes/Form", props: form_props(::Website::Theme.new)
      end

      def create
        theme = ::Website::Theme.new(theme_params)
        if theme.save
          redirect_to admin_website_theme_path(theme), notice: t("mcweb.flash.created", resource: "Theme")
        else
          render inertia: "Admin/Website/Themes/Form", props: form_props(theme), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Website/Themes/Form", props: form_props(@theme)
      end

      def update
        if @theme.update(theme_params)
          redirect_to admin_website_theme_path(@theme), notice: t("mcweb.flash.updated", resource: "Theme")
        else
          render inertia: "Admin/Website/Themes/Form", props: form_props(@theme), status: :unprocessable_entity
        end
      end

      def destroy
        @theme.destroy!
        redirect_to admin_website_themes_path, notice: t("mcweb.flash.deleted", resource: "Theme")
      end

      def activate
        @theme.activate!
        redirect_to admin_website_theme_path(@theme), notice: t("mcweb.admin.website.themes.activated", default: "Theme activated")
      end

      private

      def set_theme
        @theme = ::Website::Theme.find(params[:id])
      end

      def theme_params
        permitted = params.require(:theme).permit(:name, :key, :active, :tokens_json, tokens: {})
        if permitted[:tokens_json].present?
          permitted[:tokens] = JSON.parse(permitted.delete(:tokens_json))
        elsif permitted[:tokens].is_a?(ActionController::Parameters)
          permitted[:tokens] = permitted[:tokens].to_unsafe_h
        end
        permitted
      end

      def form_props(theme)
        {
          title: theme.persisted? ? t("mcweb.admin.website.themes.edit", default: "Edit theme") : t("mcweb.admin.website.themes.new", default: "New theme"),
          theme: {
            name: theme.name,
            key: theme.key,
            active: theme.active,
            tokens_json: JSON.pretty_generate(theme.tokens.presence || {})
          },
          submitUrl: theme.persisted? ? admin_website_theme_path(theme) : admin_website_themes_path,
          method: theme.persisted? ? "patch" : "post",
          backUrl: theme.persisted? ? admin_website_theme_path(theme) : admin_website_themes_path,
          form_errors: theme.errors.to_hash(true)
        }
      end
    end
  end
end
