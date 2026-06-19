# frozen_string_literal: true

class AdminModuleGrant < ApplicationRecord
  MODULE_KEYS = %w[forum store minecraft system website].freeze

  belongs_to :user
  belongs_to :granted_by, class_name: "User", optional: true

  validates :module_key, presence: true, inclusion: { in: MODULE_KEYS }
  validates :module_key, uniqueness: { scope: :user_id }
  validates :granted_at, presence: true
end
