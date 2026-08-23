module Website
  class Page < ApplicationRecord
    include HasPublicId
    include Website::RecoverableContent

    belongs_to :theme, class_name: "Website::Theme", foreign_key: :website_theme_id, optional: true
    belongs_to :author, class_name: "User", optional: true
    has_many :blocks, class_name: "Website::Block", foreign_key: :website_page_id, dependent: :destroy
    has_many :revisions, class_name: "Website::PageRevision", foreign_key: :website_page_id,
      dependent: :restrict_with_exception, inverse_of: :page
    has_many :nav_items, class_name: "Website::NavItem", foreign_key: :website_page_id, dependent: :nullify

    enum :status, { draft: "draft", published: "published", scheduled: "scheduled", archived: "archived" }, validate: true

    validates :slug, presence: true,
                     uniqueness: { conditions: -> { where(discarded_at: nil, purged_at: nil) } },
                     format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
    validates :title, presence: true
    validates :page_type, presence: true

    scope :published, -> { where(status: :published, discarded_at: nil, purged_at: nil) }
    scope :by_slug, ->(slug) { find_by!(slug: slug) }
    scope :cms_home, -> { published.where(page_type: "home") }
    after_commit -> { Website::NavItem.clear_frontend_cache! }
    after_commit -> { Website::HomeCache.bump! }

    def publish!(actor: nil, request_id: nil)
      result = Website::PagePublisher.call(
        page: self,
        actor: actor,
        expected_lock_version: lock_version,
        request_id: request_id || "website-model-publish-page-#{SecureRandom.uuid}"
      )
      raise ActiveRecord::RecordInvalid, self unless result.success?

      self
    end
  end
end
