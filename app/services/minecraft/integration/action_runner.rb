# frozen_string_literal: true

module Minecraft
  module Integration
    class ActionRunner < ApplicationService
      def initialize(event_key:, event_id:, payload: {})
        @event_key = event_key.to_s
        @event_id = event_id.to_s
        @payload = payload.deep_stringify_keys
      end

      def call
        return ServiceResult.success(skipped: true) if @event_id.blank?
        return ServiceResult.success(skipped: true) if Minecraft::IntegrationActionLog.exists?(event_id: @event_id)

        rules = Minecraft::IntegrationAction.for_event(@event_key)
        rules.each do |rule|
          next unless conditions_match?(rule.conditions)

          execute_actions(rule)
        end

        Minecraft::IntegrationActionLog.create!(
          event_key: @event_key,
          event_id: @event_id,
          payload: @payload,
          status: "completed"
        )

        ServiceResult.success(processed: true)
      rescue StandardError => e
        Minecraft::IntegrationActionLog.create!(
          event_key: @event_key,
          event_id: @event_id,
          payload: @payload,
          status: "failed",
          error_message: e.message
        )
        ServiceResult.failure(error: e.message)
      end

      private

      def conditions_match?(conditions)
        return true if conditions.blank?

        conditions.all? do |key, expected|
          actual = @payload.dig(*key.to_s.split("."))
          case expected
          when Hash
            expected["gte"] ? actual.to_f >= expected["gte"].to_f : actual == expected
          else
            actual.to_s == expected.to_s
          end
        end
      end

      def execute_actions(rule)
        Array(rule.actions).each do |action|
          case action["type"]
          when "set_profile_field"
            set_profile_field(action)
          when "create_notification"
            create_notification(action)
          when "grant_badge"
            grant_badge(action)
          when "enqueue_connector_task"
            enqueue_connector_task(action)
          else
            Rails.logger.info("[IntegrationAction] unhandled action type=#{action['type']}")
          end
        end
      end

      def set_profile_field(action)
        player_id = @payload["player_id"] || resolve_player_id
        return unless player_id

        profile = Minecraft::PlayerProfile.find_by_public_id(player_id)
        return unless profile

        Minecraft::ProfileFieldValue.upsert(
          { player_profile_id: profile.id, field_key: action["field_key"], value: action["value"], updated_by: "integration", created_at: Time.current, updated_at: Time.current },
          unique_by: %i[player_profile_id field_key]
        )
      end

      def create_notification(action)
        user = resolve_user
        return unless user

        user.notifications.create!(
          notification_type: action["notification_type"] || "minecraft.custom",
          title: action["title"] || I18n.t("mcweb.minecraft.notifications.default_title"),
          body: action["body"] || @event_key,
          metadata: { path: action["path"], event_key: @event_key }
        )
      end

      def enqueue_connector_task(action)
        server_id = action["server_id"].presence || @payload["server_id"]
        server = server_id.present? ? Minecraft::Server.find_by(public_id: server_id.to_s) : Minecraft::Server.order(:name).first
        return unless server

        Minecraft::ConnectorTask.create!(
          server: server,
          task_type: action["task_type"].to_s,
          delivery_id: action["delivery_id"].presence || SecureRandom.uuid,
          status: "pending",
          payload: action["payload"].presence || {}
        )
      end

      def grant_badge(action)
        user = resolve_user
        return unless user
        return if action["badge_slug"].blank?

        Community::AwardBadge.call(user: user, badge_slug: action["badge_slug"])
      end

      def resolve_player_id
        @payload["player_id"].presence || begin
          uuid = @payload["uuid"]
          platform = @payload["platform"] || "java"
          return nil unless uuid

          Minecraft::PlayerRef.resolve(uuid: uuid, platform: platform).public_id
        end
      end

      def resolve_user
        player_id = resolve_player_id
        return nil unless player_id

        Minecraft::PlayerRef.find_by_canonical(player_id)&.website_user
      end
    end
  end
end
