module Website
  class NavItem < ApplicationRecord
    CACHE_NAMESPACE = "website/navigation/v1"
    CACHE_VERSION_KEY = "#{CACHE_NAMESPACE}/version"
    belongs_to :page, class_name: "Website::Page", foreign_key: :website_page_id, optional: true

    validates :label, presence: true
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :location, presence: true
    validate :url_or_page_present
    validate :safe_url_format
    after_commit :clear_frontend_cache

    scope :visible_items, -> { where(visible: true) }
    scope :for_location, ->(location) { where(location: location) }
    scope :ordered, -> { order(:position) }

    def href
      return "/#{page.slug}" if page&.published?
      return if website_page_id.present?

      url
    end

    def self.frontend_items(location)
      Rails.cache.fetch([ CACHE_NAMESPACE, cache_version, location.to_s ]) do
        visible_items
          .for_location(location)
          .ordered
          .includes(:page)
          .filter_map do |item|
            href = item.href
            { label: item.label, href: href } if href.present?
          end
      end
    end

    def self.clear_frontend_cache!(location = nil)
      if location
        Rails.cache.delete([ CACHE_NAMESPACE, cache_version, location.to_s ])
      else
        Rails.cache.write(CACHE_VERSION_KEY, cache_version + 1)
      end
    end

    def self.cache_version
      Rails.cache.fetch(CACHE_VERSION_KEY) { 1 }.to_i
    end

    private

    def clear_frontend_cache
      self.class.clear_frontend_cache!(location)
      if saved_change_to_location?
        self.class.clear_frontend_cache!(location_before_last_save)
      end
    end

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
