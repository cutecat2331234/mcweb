# frozen_string_literal: true

module Community
  class PostAttachment < ApplicationRecord
    self.table_name = "forum_post_attachments"

    belongs_to :post, class_name: "Community::Post", foreign_key: :forum_post_id, optional: true, inverse_of: :attachments
    belongs_to :user

    has_one_attached :file
    has_one :upload_record,
      class_name: "Community::Upload",
      foreign_key: :forum_post_attachment_id,
      dependent: :nullify,
      inverse_of: :post_attachment

    validates :filename, presence: true
    validates :byte_size, numericality: { greater_than: 0 }, allow_nil: true

    scope :unlinked, -> { where(forum_post_id: nil) }
    scope :ordered, -> { order(:created_at) }

    def linked?
      forum_post_id.present?
    end

    def scan_clean?
      upload_record&.scan_clean? == true
    end

    def scan_bindable?
      scan_clean? && upload_record.status_stored?
    end

    def human_size
      ActiveSupport::NumberHelper.number_to_human_size(byte_size)
    end
  end
end
