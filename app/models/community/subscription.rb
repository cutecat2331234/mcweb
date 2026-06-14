module Community
  class Subscription < ApplicationRecord
    NOTIFICATION_LEVELS = %w[watching tracking].freeze

    belongs_to :user
    belongs_to :subscribable, polymorphic: true

    validates :user_id, uniqueness: { scope: [ :subscribable_type, :subscribable_id ] }
    validates :notification_level, inclusion: { in: NOTIFICATION_LEVELS }

    def self.subscribe!(user, subscribable, level: "watching")
      record = find_or_initialize_by(user: user, subscribable: subscribable)
      record.notification_level = level if record.new_record? || record.notification_level.blank?
      record.save!
      record
    end

    def watching?
      notification_level == "watching"
    end

    def tracking?
      notification_level == "tracking"
    end

    def self.unsubscribe!(user, subscribable)
      find_by(user: user, subscribable: subscribable)&.destroy
    end
  end
end
