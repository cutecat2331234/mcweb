# frozen_string_literal: true

class DeveloperModeRuntimeState < ApplicationRecord
  validates :configuration_digest, presence: true
  validates :observed_at, presence: true

  before_update :prevent_identity_change
  before_destroy { throw(:abort) }

  private

  def prevent_identity_change
    throw(:abort) if will_save_change_to_id?
  end
end
