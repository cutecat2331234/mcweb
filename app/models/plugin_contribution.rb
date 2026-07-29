# frozen_string_literal: true

class PluginContribution < ApplicationRecord
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/

  belongs_to :plugin_release, inverse_of: :contributions

  validates :contribution_id,
            presence: true,
            length: { maximum: 191 },
            uniqueness: { scope: :plugin_release_id }
  validates :contribution_type, presence: true, length: { maximum: 64 }
  validates :descriptor_sha256,
            presence: true,
            format: { with: SHA256_PATTERN }
  validates :schema_sha256,
            allow_nil: true,
            format: { with: SHA256_PATTERN }
  validate :descriptor_is_object

  private

  def descriptor_is_object
    errors.add(:descriptor, I18n.t("mcweb.validation_errors.must_be_an_object")) unless descriptor.is_a?(Hash)
  end
end
