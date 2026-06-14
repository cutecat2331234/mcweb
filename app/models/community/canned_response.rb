# frozen_string_literal: true

module Community
  class CannedResponse < ApplicationRecord
    belongs_to :author, class_name: "User"

    validates :title, :body, presence: true

    scope :ordered, -> { order(:title) }
  end
end
