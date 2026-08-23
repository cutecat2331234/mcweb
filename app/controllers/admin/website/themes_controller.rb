# frozen_string_literal: true

module Admin
  module Website
    class ThemesController < BaseController
      before_action -> { require_permission("website.pages.read") }
      before_action -> { require_permission("website.pages.edit") }, only: %i[new create edit update destroy]
      before_action -> { require_permission("website.pages.publish") }, only: %i[activate]
      before_action :set_theme, only: %i[show edit update destroy activate]

      def index
        themes = ::Website::Theme.order(:name)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.website.themes.title", default: "Website themes"),
          columns: [
            admin_column(:name, t("mcweb.admin.website.themes.col_name"), link: true),
            admin_column(:key, t("mcweb.admin.website.themes.col_key")),
            admin_column(:active, t("mcweb.admin.website.themes.col_active"))
          ],
          rows: themes.map do |theme|
            admin_row(
              name: theme.name,
              key: theme.key,
              active: theme.active? ? t("mcweb.labels.enabled") : t("mcweb.labels.disabled"),
              url: admin_website_theme_path(theme)
            )
          end,
          actions: current_user.permission?("website.pages.edit") ? [
            { label: t("mcweb.admin.website.themes.new", default: "New theme"), href: new_admin_website_theme_path }
          ] : []
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @theme.name,
          subtitle: @theme.key,
          fields: [
            {
              label: t("mcweb.admin.common.status"),
              value: t(@theme.active? ? "mcweb.labels.enabled" : "mcweb.labels.disabled")
            },
            { label: t("mcweb.user_copy.theme_tokens"), value: @theme.tokens.to_json.truncate(200) }
          ],
          backUrl: admin_website_themes_path,
          actions: theme_actions
        }
      end

      def new
        render inertia: "Admin/Website/Themes/Form", props: form_props(::Website::Theme.new)
      end

      def create
        theme = ::Website::Theme.new
        attrs = theme_attributes(theme)
        return render_theme_form(theme, :unprocessable_entity) if attrs.nil?

        result = ::Website::MutateTheme.call(
          operation: :create,
          theme: theme,
          actor: current_user,
          attributes: attrs
        )
        if result.success?
          redirect_to admin_website_theme_path(theme), notice: t("mcweb.flash.created", resource: t("mcweb.resources.theme"))
        else
          theme = result.value&.fetch(:theme, nil) || theme
          flash.now[:alert] = service_error_message(result)
          render_theme_form(theme, :unprocessable_entity)
        end
      end

      def edit
        render inertia: "Admin/Website/Themes/Form", props: form_props(@theme)
      end

      def update
        attrs = theme_attributes(@theme)
        return render_theme_form(@theme, :unprocessable_entity) if attrs.nil?

        expected_lock_version = attrs.delete(:lock_version)
        result = ::Website::MutateTheme.call(
          operation: :update,
          theme: @theme,
          actor: current_user,
          attributes: attrs,
          expected_lock_version: expected_lock_version
        )
        if result.success?
          theme = result.value.fetch(:theme)
          redirect_to admin_website_theme_path(theme), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.theme"))
        else
          theme = result.value&.fetch(:theme, nil) || @theme
          flash.now[:alert] = service_error_message(result)
          render_theme_form(theme, :unprocessable_entity)
        end
      end

      def destroy
        deleted = false
        ::Website::Theme.transaction do
          @theme.lock!
          unless @theme.revisions.exists?
            ::Website::Page.with_lifecycle
              .where(website_theme_id: @theme.id)
              .update_all(website_theme_id: nil)
            @theme.destroy!
            deleted = true
          end
        end

        if deleted
          redirect_to admin_website_themes_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.theme"))
        else
          redirect_to admin_website_theme_path(@theme),
            alert: t("mcweb.services.errors.website_theme_delete_blocked")
        end
      end

      def activate
        result = ::Website::MutateTheme.call(
          operation: :activate,
          theme: @theme,
          actor: current_user,
          expected_lock_version: params[:lock_version]
        )
        if result.success?
          redirect_to admin_website_theme_path(result.value.fetch(:theme)),
            notice: t("mcweb.admin.website.themes.activated", default: "Theme activated")
        else
          redirect_to admin_website_theme_path(@theme), alert: service_error_message(result)
        end
      end

      private

      def theme_actions
        actions = []
        if current_user.permission?("website.pages.edit")
          actions << { label: t("mcweb.admin.ui.edit"), href: edit_admin_website_theme_path(@theme) }
        end
        actions << {
          label: t("mcweb.admin.website.theme_version_governance.history_action"),
          href: admin_website_theme_revisions_path(@theme)
        }
        if current_user.permission?("website.pages.publish") && !@theme.active?
          actions << {
            label: t("mcweb.admin.website.themes.activate", default: "Activate"),
            href: activate_admin_website_theme_path(@theme),
            method: "post",
            data: { lock_version: @theme.lock_version }
          }
        end
        actions
      end

      def set_theme
        @theme = ::Website::Theme.find(params[:id])
      end

      def theme_attributes(theme)
        permitted = params.require(:theme).permit(:name, :key, :tokens_json, :lock_version, tokens: {})
        if permitted[:tokens_json].present?
          begin
            permitted[:tokens] = JSON.parse(permitted.delete(:tokens_json))
          rescue JSON::ParserError
            theme.errors.add(:tokens, I18n.t("mcweb.validation_errors.invalid_json"))
            return nil
          end
        elsif permitted[:tokens].is_a?(ActionController::Parameters)
          permitted[:tokens] = permitted[:tokens].to_unsafe_h
        end
        permitted
      end

      def render_theme_form(theme, status)
        render inertia: "Admin/Website/Themes/Form", props: form_props(theme), status: status
      end

      def form_props(theme)
        {
          title: theme.persisted? ? t("mcweb.admin.website.themes.edit", default: "Edit theme") : t("mcweb.admin.website.themes.new", default: "New theme"),
          theme: {
            name: theme.name,
            key: theme.key,
            tokens_json: JSON.pretty_generate(theme.tokens.presence || {}),
            lock_version: theme.persisted? ? theme.lock_version : nil
          },
          submitUrl: theme.persisted? ? admin_website_theme_path(theme) : admin_website_themes_path,
          deleteUrl: theme.persisted? && !theme.revisions.exists? ? admin_website_theme_path(theme) : nil,
          method: theme.persisted? ? "patch" : "post",
          backUrl: theme.persisted? ? admin_website_theme_path(theme) : admin_website_themes_path,
          form_errors: theme.errors.to_hash(true)
        }
      end
    end
  end
end
