# frozen_string_literal: true

class PluginFile < ApplicationRecord
  HEALTH_STATES = %w[
    healthy missing modified unknown unavailable untracked
  ].freeze
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/

  belongs_to :plugin_release, inverse_of: :files

  validates :path,
            presence: true,
            length: { maximum: 1_024 },
            uniqueness: { scope: :plugin_release_id }
  validates :byte_size,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :observed_byte_size,
            allow_nil: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sha256, presence: true, format: { with: SHA256_PATTERN }
  validates :observed_sha256,
            allow_nil: true,
            format: { with: SHA256_PATTERN }
  validates :health, inclusion: { in: HEALTH_STATES }
  validate :path_is_relative_and_portable

  private

  def path_is_relative_and_portable
    value = path.to_s
    pathnames = value.split("/")
    invalid = value.blank? ||
      value.start_with?("/", "\\") ||
      value.include?("\\") ||
      value.match?(/\A[A-Za-z]:/) ||
      value.match?(/[[:cntrl:]]/) ||
      pathnames.any? { |part| part.blank? || part.in?(%w[. ..]) }
    errors.add(:path, I18n.t("mcweb.validation_errors.must_be_a_normalized_relative_path")) if invalid
  end
end
