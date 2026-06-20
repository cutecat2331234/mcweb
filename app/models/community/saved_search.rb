# frozen_string_literal: true

module Community
  class SavedSearch < ApplicationRecord
    self.table_name = "forum_saved_searches"

    belongs_to :user

    has_many :webhook_deliveries, class_name: "Community::SavedSearchWebhookDelivery", foreign_key: :saved_search_id, dependent: :destroy

    validates :name, presence: true
    validates :query, presence: true, allow_blank: true

    scope :recent, -> { order(created_at: :desc) }
    scope :notify_daily, -> { where(notify_daily: true) }

    validates :webhook_url, allow_blank: true, format: { with: %r{\Ahttps?://.+\z}i, message: "必须是有效的 http(s) URL" }
    validate :webhook_url_public, if: -> { webhook_url.present? }

    validate :within_user_limit, on: :create

    def self.limit_for_user(user)
      limit = SiteSetting.get("forum.saved_search_limit", "20").to_i
      return Float::INFINITY if limit <= 0

      limit
    end

  private

    def within_user_limit
      limit = self.class.limit_for_user(user)
      return if limit == Float::INFINITY

      count = user.forum_saved_searches.count
      errors.add(:base, "保存搜索已达上限（#{limit.to_i}）") if count >= limit
    end

    def webhook_url_public
      return if UrlSafety.public_http_url?(webhook_url)

      errors.add(:webhook_url, "不能指向内网或本地地址")
    end
  end
end
