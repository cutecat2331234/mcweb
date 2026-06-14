# frozen_string_literal: true

module Community
  class UserIgnore < ApplicationRecord
    belongs_to :ignorer, class_name: "User"
    belongs_to :ignored, class_name: "User"

    validates :ignorer_id, uniqueness: { scope: :ignored_id }
    validate :cannot_ignore_self

    def self.ignored_user_ids(user)
      where(ignorer: user).pluck(:ignored_id)
    end

    private

    def cannot_ignore_self
      errors.add(:ignored, "cannot be yourself") if ignorer_id == ignored_id
    end
  end
end
