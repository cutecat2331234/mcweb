# frozen_string_literal: true

module Website
  class PurgeDiscardedContentJob < ApplicationJob
    queue_as :maintenance

    def perform(at: Time.current)
      [ Website::Page, Website::Article ].each do |model|
        model.purge_due(at).find_each do |content|
          Website::FinalPurge.call(
            content: content,
            actor: nil,
            reason: "retention_expired",
            confirmation: Website::FinalPurge.confirmation_for(content),
            expected_lock_version: content.lock_version,
            idempotency_key: "website-retention:#{model.model_name.element}:#{content.id}:#{content.purge_at.to_i}",
            background: true,
            at: at
          )
        end
      end
    end
  end
end
