# frozen_string_literal: true

module Website
  class ArticlePublisher < ApplicationService
    def initialize(article:, publish_at: nil, actor: nil, expected_lock_version: nil, request_id: nil)
      @article = article
      @publish_at = publish_at
      @actor = actor
      @expected_lock_version = expected_lock_version
      @request_id = request_id
    end

    def call
      Website::PublishContent.call(
        content: @article,
        actor: @actor,
        publish_at: @publish_at,
        expected_lock_version: @expected_lock_version,
        request_id: @request_id
      )
    end
  end
end
