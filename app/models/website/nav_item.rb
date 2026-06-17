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

      errors.add(:base, "must have either a page or url")
    end

    def safe_url_format
      return if url.blank?

      unless url.match?(/\A(https?:\/\/|\/[^\/])/) || url.start_with?("/")
        errors.add(:url, "格式无效，仅允许 http(s):// 或以 / 开头的站内路径")
        return
      end

      if url.match?(/\A(javascript:|data:|\/\/)/i)
        errors.add(:url, "不允许使用该协议")
      end
    end
  end
end
