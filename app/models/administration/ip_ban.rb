# frozen_string_literal: true

module Administration
  class IpBan < ApplicationRecord
    belongs_to :banned_by, class_name: "User", optional: true

    validates :ip_address, presence: true, uniqueness: true

    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

    def active?
      expires_at.nil? || expires_at > Time.current
    end
  end
end
