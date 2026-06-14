module Website
  class PageRevision < ApplicationRecord
    belongs_to :page, class_name: "Website::Page", foreign_key: :website_page_id
    belongs_to :author, class_name: "User", optional: true

    validates :revision_number, presence: true, uniqueness: { scope: :website_page_id }
    validates :snapshot, presence: true

    scope :ordered, -> { order(revision_number: :desc) }
  end
end
