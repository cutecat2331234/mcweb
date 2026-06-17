# frozen_string_literal: true

module Community
  class ApplySearchExclusions < ApplicationService
    def initialize(scope:, exclude_terms:)
      @scope = scope
      @exclude_terms = Array(exclude_terms).map(&:to_s).map(&:strip).reject(&:blank?)
    end

    def call
      scope = @scope
      @exclude_terms.each do |term|
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        scope = scope.where.not(
          <<~SQL.squish,
            forum_topics.title ILIKE :pattern OR EXISTS (
              SELECT 1 FROM forum_posts
              WHERE forum_posts.forum_topic_id = forum_topics.id
              AND forum_posts.status = 'published'
              AND forum_posts.body ILIKE :pattern
            )
          SQL
          pattern: pattern
        )
      end
      ServiceResult.success(scope)
    end

    def self.on_posts(scope, exclude_terms:)
      scope = scope.joins(:topic)
      Array(exclude_terms).map(&:to_s).map(&:strip).reject(&:blank?).each do |term|
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        scope = scope.where.not(
          "forum_topics.title ILIKE :pattern OR forum_posts.body ILIKE :pattern",
          pattern: pattern
        )
      end
      scope
    end
  end
end
