# frozen_string_literal: true

require "mcweb/plugins/manifest"

class PluginStorageObject < ApplicationRecord
  KEY_PATTERN = /\A[a-z0-9][a-z0-9._\/-]*\z/

  has_encrypted :metadata, type: :json, encrypted_attribute: :encrypted_metadata
  has_one_attached :file, dependent: :purge_later

  before_validation :assign_public_id, on: :create

  validates :public_id,
            presence: true,
            uniqueness: true,
            format: {
              with: /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
            }
  validates :owner_plugin_id,
            presence: true,
            length: { maximum: 191 },
            format: { with: Mcweb::Plugins::Manifest::ID_PATTERN }
  validates :key,
            presence: true,
            length: { maximum: 512 },
            format: { with: KEY_PATTERN },
            uniqueness: { scope: :owner_plugin_id }
  validates :content_type, presence: true, length: { maximum: 255 }
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :checksum_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :key_must_not_traverse
  validate :metadata_must_be_mapping

  scope :owned_by, ->(plugin_id) { where(owner_plugin_id: plugin_id.to_s) }
  scope :available, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def key_must_not_traverse
    segments = key.to_s.split("/")
    errors.add(:key, I18n.t("mcweb.validation_errors.must_not_traverse_directories")) if segments.include?("..") || key.to_s.include?("\\")
  end

  def metadata_must_be_mapping
    errors.add(:metadata, I18n.t("mcweb.validation_errors.must_be_a_mapping")) unless metadata.is_a?(Hash)
  end
end
