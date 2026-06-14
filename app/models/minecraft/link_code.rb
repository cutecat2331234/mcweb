module Minecraft
  class LinkCode < ApplicationRecord
    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id
    belongs_to :used_by, class_name: "User", optional: true

    attr_reader :raw_code

    validates :code_digest, presence: true, uniqueness: true
    validates :minecraft_uuid, :minecraft_username, presence: true
    validates :expires_at, presence: true

    scope :unused, -> { where(used_at: nil) }
    scope :valid_codes, -> { unused.where("expires_at > ?", Time.current) }

    before_validation :generate_code, on: :create
    before_validation :set_expiry, on: :create

    def self.find_by_code(code)
      find_by(code_digest: digest_code(code))
    end

    def self.digest_code(code)
      Digest::SHA256.hexdigest(code.to_s.strip.upcase)
    end

    def expired?
      expires_at <= Time.current
    end

    def used?
      used_at.present?
    end

    def redeem!(user)
      return false if expired? || used?

      transaction do
        update!(used_at: Time.current, used_by: user)
        Identity.create!(
          user: user,
          uuid: minecraft_uuid,
          username: minecraft_username,
          identity_type: identity_type,
          server: server,
          linked_at: Time.current
        )
      end
      true
    end

    private

    def generate_code
      return if code_digest.present?

      @raw_code = SecureRandom.alphanumeric(8).upcase
      self.code_digest = self.class.digest_code(@raw_code)
    end

    def set_expiry
      self.expires_at ||= 15.minutes.from_now
    end
  end
end
