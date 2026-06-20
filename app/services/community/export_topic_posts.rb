# frozen_string_literal: true

module Community
  class ExportTopicPosts < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      lines = [ I18n.t("mcweb.forum.exports.posts_header") ]
      @topic.posts.where(status: :published).order(:floor_number).includes(:user).find_each do |post|
        lines << [
          post.floor_number,
          escape_csv(post.user&.username),
          post.created_at.iso8601,
          escape_csv(post.body)
        ].join(",")
      end

      ServiceResult.success(csv: lines.join("\n"))
    end

    private

    def escape_csv(value)
      text = value.to_s
      return text unless text.include?(",") || text.include?('"') || text.include?("\n")

      "\"#{text.gsub('"', '""')}\""
    end
  end
end
