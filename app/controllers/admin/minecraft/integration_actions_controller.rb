# frozen_string_literal: true

module Admin
  module Minecraft
    class IntegrationActionsController < BaseController
      before_action -> { require_permission("minecraft.servers.manage") }
      before_action :set_action, only: %i[edit update destroy]

      def index
        actions = ::Minecraft::IntegrationAction.order(priority: :desc, name: :asc)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.minecraft.integration_actions"),
          columns: [
            admin_column(:name, t("mcweb.admin.minecraft.col_name"), link: true),
            admin_column(:event_key, t("mcweb.admin.minecraft.col_event")),
            admin_column(:enabled, t("mcweb.admin.minecraft.col_enabled")),
            admin_column(:priority, t("mcweb.admin.minecraft.col_priority"))
          ],
          rows: actions.map do |action|
            admin_row(
              name: action.name,
              event_key: action.event_key,
              enabled: action.enabled? ? I18n.t("mcweb.labels.yes") : I18n.t("mcweb.labels.no"),
              priority: action.priority.to_s,
              url: edit_admin_minecraft_integration_action_path(action)
            )
          end,
          actions: [ { label: t("mcweb.admin.minecraft.new_rule"), href: new_admin_minecraft_integration_action_path } ]
        }
      end

      def new
        render inertia: "Admin/Minecraft/IntegrationActions/Form", props: form_props(::Minecraft::IntegrationAction.new(enabled: true))
      end

      def edit
        render inertia: "Admin/Minecraft/IntegrationActions/Form", props: form_props(@action)
      end

      def create
        parsed = parsed_action_params
        unless parsed
          action = ::Minecraft::IntegrationAction.new(action_params.except(:conditions_json, :actions_json))
          action.errors.add(:base, "JSON 格式无效")
          return render inertia: "Admin/Minecraft/IntegrationActions/Form", props: form_props(action), status: :unprocessable_entity
        end

        action = ::Minecraft::IntegrationAction.new(parsed)
        if action.save
          redirect_to admin_minecraft_integration_actions_path, notice: t("mcweb.flash.rule_created")
        else
          render inertia: "Admin/Minecraft/IntegrationActions/Form", props: form_props(action), status: :unprocessable_entity
        end
      end

      def update
        parsed = parsed_action_params
        unless parsed
          @action.assign_attributes(action_params.except(:conditions_json, :actions_json))
          @action.errors.add(:base, "JSON 格式无效")
          return render inertia: "Admin/Minecraft/IntegrationActions/Form", props: form_props(@action), status: :unprocessable_entity
        end

        if @action.update(parsed)
          redirect_to admin_minecraft_integration_actions_path, notice: t("mcweb.flash.rule_updated")
        else
          render inertia: "Admin/Minecraft/IntegrationActions/Form", props: form_props(@action), status: :unprocessable_entity
        end
      end

      def destroy
        @action.destroy!
        redirect_to admin_minecraft_integration_actions_path, notice: t("mcweb.flash.rule_deleted")
      end

      private

      def set_action
        @action = ::Minecraft::IntegrationAction.find(params[:id])
      end

      def parsed_action_params
        raw = action_params.to_h
        raw[:conditions] = JSON.parse(raw[:conditions_json].presence || "{}")
        raw[:actions] = JSON.parse(raw[:actions_json].presence || "[]")
        raw.except(:conditions_json, :actions_json)
      rescue JSON::ParserError
        nil
      end

      def action_params
        params.expect(integration_action: %i[name event_key conditions_json actions_json enabled priority])[:integration_action]
      end

      def form_props(action)
        {
          title: action.persisted? ? t("mcweb.admin.minecraft.edit_rule") : t("mcweb.admin.minecraft.new_rule"),
          integrationAction: {
            name: action.name.to_s,
            event_key: action.event_key.to_s,
            conditions_json: JSON.pretty_generate(action.conditions.presence || {}),
            actions_json: JSON.pretty_generate(action.actions.presence || []),
            enabled: action.enabled.nil? ? true : action.enabled,
            priority: action.priority || 0
          },
          submitUrl: action.persisted? ? admin_minecraft_integration_action_path(action) : admin_minecraft_integration_actions_path,
          method: action.persisted? ? "patch" : "post",
          backUrl: admin_minecraft_integration_actions_path
        }
      end
    end
  end
end
