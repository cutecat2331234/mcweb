# frozen_string_literal: true

module Minecraft
  class ExpirePlayerAccessRulesJob < ApplicationJob
    queue_as :minecraft

    def perform
      Minecraft::PlayerAccessRule.due_for_expiry.find_each do |rule|
        Minecraft::SetPlayerAccessRule.call(
          server: rule.server,
          desired_state: false,
          rule: rule,
          reason: "configured_expiry_reached",
          idempotency_key: "expiry:#{rule.public_id}:#{rule.expires_at.to_i}",
          expected_lock_version: rule.lock_version
        )
      end
    end
  end
end
