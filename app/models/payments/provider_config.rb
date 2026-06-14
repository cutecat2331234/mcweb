module Payments
  class ProviderConfig < ApplicationRecord
    has_encrypted :credentials, type: :json, encrypted_attribute: :encrypted_credentials

    validates :provider, presence: true, uniqueness: true

    scope :enabled_providers, -> { where(enabled: true) }

    def self.for_provider(provider)
      find_by(provider: provider)
    end

    def credentials_hash
      credentials.is_a?(Hash) ? credentials : {}
    end
  end
end
