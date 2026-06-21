# frozen_string_literal: true

module Website
  class PublishScheduledContentJob < ApplicationJob
    queue_as :website

    def perform
      publish_due_pages
      publish_due_articles
    end

    private

    def publish_due_pages
      Website::Page.where(status: "scheduled")
        .where.not(scheduled_at: nil)
        .where(scheduled_at: ..Time.current)
        .find_each do |page|
          Website::PagePublisher.call(page: page, publish_at: nil)
        end
    end

    def publish_due_articles
      Website::Article.where(status: "scheduled")
        .where.not(scheduled_at: nil)
        .where(scheduled_at: ..Time.current)
        .find_each do |article|
          Website::ArticlePublisher.call(article: article, publish_at: nil)
        end
    end
  end
end
