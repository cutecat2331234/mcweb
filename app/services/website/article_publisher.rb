# frozen_string_literal: true

module Website
  class ArticlePublisher < ApplicationService
    def initialize(article:, publish_at: nil, actor: nil)
      @article = article
      @publish_at = publish_at
      @actor = actor
    end

    def call
      if @publish_at.present? && @publish_at.future?
        schedule_article
      else
        publish_now
      end
    end

    private

    def publish_now
      @article.update!(
        status: "published",
        published_at: Time.current,
        scheduled_at: nil
      )

      log_action("website.article.published")
      ServiceResult.success(@article)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def schedule_article
      @article.update!(
        status: "scheduled",
        scheduled_at: @publish_at,
        published_at: nil
      )

      log_action("website.article.scheduled", scheduled_at: @publish_at.iso8601)
      ServiceResult.success(@article)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def log_action(action, metadata = {})
      Administration::AuditLogger.call(
        actor: @actor,
        action: action,
        resource: @article,
        metadata: metadata
      )
    end
  end
end
