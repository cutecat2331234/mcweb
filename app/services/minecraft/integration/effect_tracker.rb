# frozen_string_literal: true

module Minecraft
  module Integration
    class EffectTracker
      def initialize(log:, event_id:)
        @log = log
        @event_id = event_id.to_s
      end

      def completed?(effect_key)
        completed_effects.include?(effect_key)
      end

      def mark_completed!(effect_key)
        return if completed?(effect_key)

        @log.update!(completed_effects: completed_effects + [ effect_key ])
      end

      def fingerprint(rule:, action:, index:)
        Digest::SHA256.hexdigest(
          [
            @event_id,
            rule.id,
            index,
            action["type"],
            action.except("type").sort.to_json
          ].join("|")
        )
      end

      def delivery_id_for(effect_key)
        "integration-#{@event_id}-#{effect_key.first(32)}"
      end

      private

      def completed_effects
        Array(@log.completed_effects)
      end
    end
  end
end
