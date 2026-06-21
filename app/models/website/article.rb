module Website
  class Article < ApplicationRecord
    include HasPublicId

    belongs_to :author, class_name: "User", optional: true

    enum :status, { draft: "draft", published: "published", scheduled: "scheduled", archived: "archived" }, validate: true

    validates :slug, presence: true, uniqueness: { scope: :article_type },
                     format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
    validates :title, presence: true
    validates :article_type, presence: true

    scope :published, -> { where(status: :published) }
    scope :by_type, ->(type) { where(article_type: type) }

    def publish!
      update!(status: :published, published_at: Time.current)
    end
  end
end
