module Website
  class Article < ApplicationRecord
    include HasPublicId
    include Website::RecoverableContent

    belongs_to :author, class_name: "User", optional: true
    has_many :revisions, class_name: "Website::ArticleRevision", foreign_key: :website_article_id,
      dependent: :restrict_with_exception, inverse_of: :article

    enum :status, { draft: "draft", published: "published", scheduled: "scheduled", archived: "archived" }, validate: true

    validates :slug, presence: true,
                     uniqueness: { conditions: -> { where(discarded_at: nil, purged_at: nil) } },
                     format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
    validates :title, presence: true
    validates :article_type, presence: true

    scope :published, -> { where(status: :published, discarded_at: nil, purged_at: nil) }
    scope :by_type, ->(type) { where(article_type: type) }
    after_commit -> { Website::HomeCache.bump! }

    def publish!(actor: nil, request_id: nil)
      result = Website::ArticlePublisher.call(
        article: self,
        actor: actor,
        expected_lock_version: lock_version,
        request_id: request_id || "website-model-publish-article-#{SecureRandom.uuid}"
      )
      raise ActiveRecord::RecordInvalid, self unless result.success?

      self
    end
  end
end
