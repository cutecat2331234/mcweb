# frozen_string_literal: true

module Community
  class CannedResponse < ApplicationRecord
    belongs_to :author, class_name: "User"

    validates :title, :body, presence: true

    scope :ordered, -> { order(:title) }

    # Substitute placeholders against a topic's context so moderators get a
    # ready-to-send reply (Discourse-style {username}/{topic} variables).
    def render_for(topic: nil)
      text = body.to_s
      return text unless topic

      text
        .gsub("{username}", topic.user&.username.to_s)
        .gsub("{topic}", topic.title.to_s)
        .gsub("{site_name}", SiteSetting.get("general.site_name", "").to_s)
    end
  end
end
