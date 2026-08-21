# frozen_string_literal: true

module Community
  class MessageRevision < ApplicationRecord
    self.table_name = "forum_message_revisions"

    has_encrypted :body, encrypted_attribute: :encrypted_body

    belongs_to :message,
      class_name: "Community::Message",
      foreign_key: :forum_message_id,
      inverse_of: :revisions
    belongs_to :editor, class_name: "User"

    validates :body, presence: true
    validates :revision,
      numericality: { only_integer: true, greater_than: 0 },
      uniqueness: { scope: :forum_message_id }
    validates :content_digest, format: { with: /\A[0-9a-f]{64}\z/ }

    before_update :prevent_mutation
    before_destroy :prevent_mutation

    def digest_valid?
      ActiveSupport::SecurityUtils.secure_compare(
        content_digest,
        Digest::SHA256.hexdigest(body.to_s)
      )
    end

    private

    def prevent_mutation
      errors.add(:base, :immutable)
      throw(:abort)
    end
  end
end
