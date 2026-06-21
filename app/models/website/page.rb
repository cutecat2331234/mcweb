module Website
  class Page < ApplicationRecord
    include HasPublicId

    belongs_to :theme, class_name: "Website::Theme", foreign_key: :website_theme_id, optional: true
    belongs_to :author, class_name: "User", optional: true
    has_many :blocks, class_name: "Website::Block", foreign_key: :website_page_id, dependent: :destroy
    has_many :revisions, class_name: "Website::PageRevision", foreign_key: :website_page_id, dependent: :destroy
    has_many :nav_items, class_name: "Website::NavItem", foreign_key: :website_page_id, dependent: :nullify

    enum :status, { draft: "draft", published: "published", scheduled: "scheduled", archived: "archived" }, validate: true

    validates :slug, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
    validates :title, presence: true
    validates :page_type, presence: true

    scope :published, -> { where(status: :published) }
    scope :by_slug, ->(slug) { find_by!(slug: slug) }
    scope :cms_home, -> { published.where(page_type: "home") }

    def publish!
      update!(status: :published, published_at: Time.current)
    end

    def create_revision!(author:)
      revisions.create!(
        author: author,
        revision_number: next_revision_number,
        snapshot: snapshot_data
      )
    end

    private

    def next_revision_number
      (revisions.maximum(:revision_number) || 0) + 1
    end

    def snapshot_data
      {
        title: title,
        slug: slug,
        status: status,
        seo: seo,
        translations: translations,
        blocks: blocks.order(:position).map { |b| b.attributes.slice("block_type", "position", "settings", "translations", "visible") }
      }
    end
  end
end
