# frozen_string_literal: true

class PluginRelease < ApplicationRecord
  STATES = %w[active disabled rollback uninstalled].freeze
  HEALTH_STATES = %w[healthy changed missing unavailable untracked].freeze
  DIGEST_SOURCES = %w[receipt derived].freeze
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/

  belongs_to :plugin_installation
  has_many :contributions,
           class_name: "PluginContribution",
           dependent: :delete_all,
           inverse_of: :plugin_release
  has_many :files,
           class_name: "PluginFile",
           dependent: :delete_all,
           inverse_of: :plugin_release

  validates :plugin_id, presence: true, length: { maximum: 191 }
  validates :version, presence: true, length: { maximum: 128 }
  validates :api_version, presence: true, length: { maximum: 32 }
  validates :state, inclusion: { in: STATES }
  validates :health, inclusion: { in: HEALTH_STATES }
  validates :package_digest_source, inclusion: { in: DIGEST_SOURCES }
  validates :manifest_sha256, :package_sha256,
            presence: true,
            format: { with: SHA256_PATTERN }
  validates :observed_at, presence: true
  validate :manifest_descriptor_is_object
  validate :diagnostics_are_array

  scope :current, -> { where.not(state: "rollback") }
  scope :ordered, -> { order(:plugin_id, observed_at: :desc, id: :desc) }

  private

  def manifest_descriptor_is_object
    errors.add(:manifest_descriptor, I18n.t("mcweb.validation_errors.must_be_an_object")) unless
      manifest_descriptor.is_a?(Hash)
  end

  def diagnostics_are_array
    errors.add(:diagnostics, I18n.t("mcweb.validation_errors.must_be_an_array")) unless diagnostics.is_a?(Array)
  end
end
