# frozen_string_literal: true

module Community
  class UserSilence < ApplicationRecord
    belongs_to :user
    belongs_to :created_by, class_name: "User"

    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

    def self.silenced?(user)
      return false unless user

      active.exists?(user: user)
    end

    def active?
      expires_at.nil? || expires_at > Time.current
    end
  end
end
