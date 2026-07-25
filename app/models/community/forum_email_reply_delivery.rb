# frozen_string_literal: true

module Community
  class ForumEmailReplyDelivery < ApplicationRecord
    self.table_name = "forum_email_reply_deliveries"

    STATUSES = %w[processing posted rejected].freeze

    belongs_to :inbound_email, class_name: "ActionMailbox::InboundEmail",
      foreign_key: :action_mailbox_inbound_email_id, optional: true
    belongs_to :reply_address, class_name: "Community::ForumEmailReplyAddress",
      foreign_key: :forum_email_reply_address_id, optional: true
    belongs_to :post, class_name: "Community::Post", foreign_key: :forum_post_id, optional: true

    validates :message_id_digest, presence: true
    validates :status, inclusion: { in: STATUSES }

    def posted?
      status == "posted"
    end

    def rejected?
      status == "rejected"
    end
  end
end
