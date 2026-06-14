module Payments
  class Attempt < ApplicationRecord
    belongs_to :payment_record, class_name: "Payments::Record"

    validates :status, presence: true

    scope :recent, -> { order(created_at: :desc) }
  end
end
