# frozen_string_literal: true

class PluginGeneration < ApplicationRecord
  STATES = %w[pending active superseded rolling_back rolled_back failed].freeze
  ACTIONS = %w[
    boot install upgrade enable disable uninstall rollback reconcile recover
  ].freeze

  belongs_to :initiated_by, class_name: "User", optional: true
  belongs_to :parent_generation, class_name: "PluginGeneration", optional: true
  has_many :process_acks,
           class_name: "PluginProcessAck",
           dependent: :delete_all,
           inverse_of: :plugin_generation

  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: true
  validates :state, inclusion: { in: STATES }
  validates :action, inclusion: { in: ACTIONS }
  validates :minimum_ack_ratio,
            numericality: {
              greater_than: 0,
              less_than_or_equal_to: 1
            }
  validates :deadline_at, presence: true
  validate :plugin_state_payloads_are_well_formed

  scope :ordered, -> { order(number: :desc) }
  scope :actionable, -> { where(state: %w[pending rolling_back]) }

  def terminal?
    state.in?(%w[active superseded rolled_back failed])
  end

  private

  def plugin_state_payloads_are_well_formed
    errors.add(:desired_plugins, I18n.t("mcweb.validation_errors.must_be_an_object")) unless desired_plugins.is_a?(Hash)
    errors.add(:previous_plugins, I18n.t("mcweb.validation_errors.must_be_an_object")) unless previous_plugins.is_a?(Hash)
    unless expected_process_uids.is_a?(Array) &&
        expected_process_uids.all? { |value| value.is_a?(String) && value.present? }
      errors.add(:expected_process_uids, I18n.t("mcweb.validation_errors.must_contain_process_identifiers"))
    end
  end
end
