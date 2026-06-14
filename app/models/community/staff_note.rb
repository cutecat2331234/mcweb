# frozen_string_literal: true

module Community
  class StaffNote < ApplicationRecord
    self.table_name = "forum_staff_notes"

    belongs_to :user
    belongs_to :author, class_name: "User"

    validates :body, presence: true

    scope :recent, -> { order(created_at: :desc) }
  end
end
