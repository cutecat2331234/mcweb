# frozen_string_literal: true

require "mcweb/plugins/manifest"

class PluginSettingVersion < ApplicationRecord
  CHANGE_KINDS = %w[update migration rollback].freeze

  has_encrypted :values, type: :json, encrypted_attribute: :encrypted_values

  belongs_to :actor, class_name: "User", optional: true
  belongs_to :migration_source, class_name: "PluginSettingVersion", optional: true
  belongs_to :rollback_source, class_name: "PluginSettingVersion", optional: true

  validates :plugin_id,
    presence: true,
    length: { maximum: 191 },
    format: { with: Mcweb::Plugins::Manifest::ID_PATTERN }
  validates :schema_version,
    presence: true,
    length: { maximum: 32 },
    format: { with: /\A[1-9]\d{0,8}\z/ }
  validates :schema_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validates :change_kind, inclusion: { in: CHANGE_KINDS }
  validates :revision, uniqueness: { scope: %i[plugin_id schema_version] }
  validate :values_must_be_mapping
  validate :source_matches_change_kind

  before_update :prevent_mutation
  before_destroy :prevent_mutation

  scope :for_namespace, ->(plugin_id, schema_version) {
    where(plugin_id: plugin_id.to_s, schema_version: schema_version.to_s)
  }
  scope :newest_first, -> { order(revision: :desc, id: :desc) }

  def values_hash
    values.is_a?(Hash) ? values.deep_stringify_keys : values
  end

  private

  def values_must_be_mapping
    errors.add(:values, I18n.t("mcweb.validation_errors.must_be_a_mapping")) unless values.is_a?(Hash)
  end

  def source_matches_change_kind
    if migration_source_id.present? != (change_kind == "migration")
      errors.add(:migration_source, I18n.t("mcweb.validation_errors.must_be_present_only_for_migration_versions"))
    end
    if rollback_source_id.present? != (change_kind == "rollback")
      errors.add(:rollback_source, I18n.t("mcweb.validation_errors.must_be_present_only_for_rollback_versions"))
    end
  end

  def prevent_mutation
    errors.add(:base, I18n.t("mcweb.validation_errors.plugin_setting_versions_are_immutable"))
    throw(:abort)
  end
end
