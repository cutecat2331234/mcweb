# frozen_string_literal: true

module Community
  class PostAttachment < ApplicationRecord
    self.table_name = "forum_post_attachments"

    belongs_to :post, class_name: "Community::Post", foreign_key: :forum_post_id, optional: true, inverse_of: :attachments
    belongs_to :user

    has_one_attached :file

    validates :filename, presence: true
    validates :byte_size, numericality: { greater_than: 0 }, allow_nil: true

    scope :unlinked, -> { where(forum_post_id: nil) }
    scope :ordered, -> { order(:created_at) }

    def linked?
      forum_post_id.present?
    end

    def human_size
      ActiveSupport::NumberHelper.number_to_human_size(byte_size)
    end
  end
end
