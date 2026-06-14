module Community
  class Subscription < ApplicationRecord
    belongs_to :user
    belongs_to :subscribable, polymorphic: true

    validates :user_id, uniqueness: { scope: [ :subscribable_type, :subscribable_id ] }

    def self.subscribe!(user, subscribable)
      find_or_create_by!(user: user, subscribable: subscribable)
    end

    def self.unsubscribe!(user, subscribable)
      find_by(user: user, subscribable: subscribable)&.destroy
    end
  end
end
