# frozen_string_literal: true

module Website
  class ArticleRevision < ApplicationRecord
    EVENT_TYPES = Website::PageRevision::EVENT_TYPES

    belongs_to :article, class_name: "Website::Article", foreign_key: :website_article_id,
      inverse_of: :revisions
    belongs_to :author, class_name: "User", optional: true

    validates :revision_number, presence: true, uniqueness: { scope: :website_article_id }
    validates :snapshot, presence: true
    validates :event_type, inclusion: { in: EVENT_TYPES }
    validates :reason, length: { maximum: 1_000 }, allow_nil: true
    validates :request_id_digest,
      format: { with: Website::RecoverableContent::IDEMPOTENCY_DIGEST_PATTERN },
      allow_nil: true,
      uniqueness: { scope: :website_article_id }
    validates :operation_digest,
      format: { with: Website::RecoverableContent::IDEMPOTENCY_DIGEST_PATTERN },
      allow_nil: true
    validate :idempotency_digest_pair

    before_update :prevent_mutation
    before_destroy :prevent_mutation

    scope :ordered, -> { order(revision_number: :desc) }

    private

    def prevent_mutation
      errors.add(:base, I18n.t("mcweb.validation_errors.website_revision_immutable"))
      throw(:abort)
    end

    def idempotency_digest_pair
      return if request_id_digest.present? == operation_digest.present?

      errors.add(:base, I18n.t("mcweb.validation_errors.website_revision_idempotency_pair"))
    end
  end
end
