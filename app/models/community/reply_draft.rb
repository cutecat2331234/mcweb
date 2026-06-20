# frozen_string_literal: true

module Community
  class ReplyDraft < ApplicationRecord
    belongs_to :user
    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id

    validates :user_id, uniqueness: { scope: :forum_topic_id }

    def attachment_id_list
      Array(attachment_ids).map(&:to_i).uniq.reject(&:zero?)
    end

    def attachment_id_list=(ids)
      self.attachment_ids = Array(ids).map(&:to_i).uniq.reject(&:zero?)
    end
  end
end
