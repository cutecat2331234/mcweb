# frozen_string_literal: true

module Website
  class PagePublisher < ApplicationService
    def initialize(page:, publish_at: nil, actor: nil)
      @page = page
      @publish_at = publish_at
      @actor = actor
    end

    def call
      if @publish_at.present? && @publish_at.future?
        schedule_page
      else
        publish_now
      end
    end

    private

    def publish_now
      @page.update!(
        status: "published",
        published_at: Time.current,
        scheduled_at: nil
      )

      log_action("website.page.published")
      ServiceResult.success(@page)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def schedule_page
      @page.update!(
        status: "scheduled",
        scheduled_at: @publish_at,
        published_at: nil
      )

      log_action("website.page.scheduled", scheduled_at: @publish_at.iso8601)
      ServiceResult.success(@page)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def log_action(action, metadata = {})
      Administration::AuditLogger.call(
        actor: @actor,
        action: action,
        resource: @page,
        metadata: metadata
      )
    end
  end
end
