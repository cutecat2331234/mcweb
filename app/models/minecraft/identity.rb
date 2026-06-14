module Minecraft
  class Identity < ApplicationRecord
    belongs_to :user
    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id, optional: true

    validates :uuid, presence: true, uniqueness: { scope: :identity_type }
    validates :username, presence: true
    validates :identity_type, presence: true

    scope :for_user, ->(user) { where(user: user) }
  end
end
