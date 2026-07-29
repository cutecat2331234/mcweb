module Website
  class NavItem < ApplicationRecord
    belongs_to :page, class_name: "Website::Page", foreign_key: :website_page_id, optional: true

    validates :label, presence: true
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :location, presence: true
    validate :url_or_page_present
    validate :safe_url_format

    scope :visible_items, -> { where(visible: true) }
    scope :for_location, ->(location) { where(location: location) }
    scope :ordered, -> { order(:position) }

    def href
      page&.slug ? "/#{page.slug}" : url
    end

    private

    def url_or_page_present
      return if page.present? || url.present?

      errors.add(:base, I18n.t("mcweb.validation_errors.website_nav_target_required"))
    end

    def safe_url_format
      return if url.blank?

      unless url.match?(/\A(https?:\/\/|\/[^\/])/) || url.start_with?("/")
        errors.add(:url, I18n.t("mcweb.validation_errors.website_nav_url_format"))
        return
      end

      if url.match?(/\A(javascript:|data:|vbscript:|\/\/)/i)
        errors.add(:url, I18n.t("mcweb.validation_errors.website_nav_url_scheme"))
      end
    end
  end
end
