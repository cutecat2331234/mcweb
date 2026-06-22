# frozen_string_literal: true

module Minecraft
  module Integration
    class ActionRunner < ApplicationService
      STALE_PROCESSING_AFTER = 10.minutes

      def self.acquire_or_enqueue(event_key:, event_id:, payload: {})
        return ServiceResult.failure(error: "event_id required") if event_id.blank?

        existing = Minecraft::IntegrationActionLog.find_by(event_id: event_id)
        if existing&.status.in?(%w[completed processing failed])
          return ServiceResult.success(skipped: true)
        end

        unless existing
          begin
            Minecraft::IntegrationActionLog.create!(
              event_key: event_key.to_s,
              event_id: event_id.to_s,
              payload: payload.deep_stringify_keys,
              status: "processing"
            )
          rescue ActiveRecord::RecordNotUnique
            existing = Minecraft::IntegrationActionLog.find_by!(event_id: event_id)
            return ServiceResult.success(skipped: true) if existing.status.in?(%w[completed processing failed])
          end
        end

        Minecraft::RunIntegrationActionJob.perform_later(
          event_key: event_key,
          event_id: event_id,
          payload: payload
        )
        ServiceResult.success(queued: true)
      end

      def initialize(event_key:, event_id:, payload: {})
        @event_key = event_key.to_s
        @event_id = event_id.to_s
        @payload = payload.deep_stringify_keys
      end

      def call
        return ServiceResult.success(skipped: true) if @event_id.blank?

        log = acquire_log!
        return ServiceResult.success(skipped: true) unless log

        tracker = EffectTracker.new(log: log, event_id: @event_id)
        pending_effects = []

        Minecraft::IntegrationAction.for_event(@event_key).each do |rule|
          next unless conditions_match?(rule.conditions)

          pending_effects.concat(execute_actions(rule, tracker))
        end

        if pending_effects.any?
          log.update!(
            status: "failed",
            error_message: "pending effects (#{pending_effects.size})"
          )
          return ServiceResult.failure(error: "pending_effects")
        end

        log.update!(status: "completed", error_message: nil)
        ServiceResult.success(processed: true)
      rescue StandardError => e
        log = Minecraft::IntegrationActionLog.find_by(event_id: @event_id)
        log.update!(status: "failed", error_message: e.message) if log&.status == "processing"
        ServiceResult.failure(error: e.message)
      end

      private

      def acquire_log!
        existing = Minecraft::IntegrationActionLog.find_by(event_id: @event_id)
        if existing
          case existing.status
          when "completed"
            return nil
          when "processing"
            if existing.updated_at < STALE_PROCESSING_AFTER.ago
              existing.update!(status: "processing", error_message: nil)
              return existing
            end
            return nil
          when "failed"
            existing.update!(status: "processing", error_message: nil)
            return existing
          else
            existing.update!(status: "processing", error_message: nil)
            return existing
          end
        end

        Minecraft::IntegrationActionLog.create!(
          event_key: @event_key,
          event_id: @event_id,
          payload: @payload,
          status: "processing"
        )
      rescue ActiveRecord::RecordNotUnique
        existing = Minecraft::IntegrationActionLog.find_by!(event_id: @event_id)
        return nil if existing.status == "completed"
        if existing.status == "processing" && existing.updated_at >= STALE_PROCESSING_AFTER.ago
          return nil
        end

        existing.update!(status: "processing", error_message: nil)
        existing
      end

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

      def execute_actions(rule, tracker)
        pending = []

        Array(rule.actions).each_with_index do |action, index|
          effect_key = tracker.fingerprint(rule: rule, action: action, index: index)
          next if tracker.completed?(effect_key)

          if apply_action(action, tracker, effect_key)
            tracker.mark_completed!(effect_key)
          else
            pending << effect_key
          end
        end

        pending
      end

      def apply_action(action, tracker, effect_key)
        case action["type"]
        when "set_profile_field"
          set_profile_field(action)
        when "create_notification"
          create_notification(action, effect_key: effect_key)
        when "grant_badge"
          grant_badge(action)
        when "enqueue_connector_task"
          enqueue_connector_task(action, tracker: tracker, effect_key: effect_key)
        else
          Rails.logger.info("[IntegrationAction] unhandled action type=#{action['type']}")
          false
        end
      end

      def set_profile_field(action)
        player_id = @payload["player_id"] || resolve_player_id
        return false unless player_id

        profile = Minecraft::PlayerProfile.find_by_public_id(player_id)
        return false unless profile

        Minecraft::ProfileFieldValue.upsert(
          {
            player_profile_id: profile.id,
            field_key: action["field_key"],
            value: action["value"],
            updated_by: "integration",
            created_at: Time.current,
            updated_at: Time.current
          },
          unique_by: %i[player_profile_id field_key]
        )
        true
      end

      def create_notification(action, effect_key:)
        user = resolve_user
        return false unless user

        integration_key = "integration:#{@event_id}:#{effect_key}"
        return true if user.notifications.exists?(["metadata ->> 'integration_effect_key' = ?", integration_key])

        user.notifications.create!(
          notification_type: action["notification_type"] || "minecraft.custom",
          title: action["title"] || I18n.t("mcweb.minecraft.notifications.default_title"),
          body: action["body"] || @event_key,
          metadata: {
            path: action["path"],
            event_key: @event_key,
            integration_effect_key: integration_key
          }
        )
        true
      end

      def enqueue_connector_task(action, tracker:, effect_key:)
        server_id = action["server_id"].presence || @payload["server_id"]
        server = server_id.present? ? Minecraft::Server.find_by(public_id: server_id.to_s) : Minecraft::Server.order(:name).first
        return false unless server

        delivery_id = action["delivery_id"].presence || tracker.delivery_id_for(effect_key)
        return true if Minecraft::ConnectorTask.exists?(delivery_id: delivery_id)

        Minecraft::ConnectorTask.create!(
          server: server,
          task_type: action["task_type"].to_s,
          delivery_id: delivery_id,
          status: "pending",
          payload: action["payload"].presence || {}
        )
        true
      end

      def grant_badge(action)
        user = resolve_user
        return false unless user
        return false if action["badge_slug"].blank?

        Community::AwardBadge.call(user: user, badge_slug: action["badge_slug"]).success?
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
