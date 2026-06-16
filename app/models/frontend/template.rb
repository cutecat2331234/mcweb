# frozen_string_literal: true

module Frontend
  class Template < ApplicationRecord
    self.table_name = "frontend_templates"

    STATUSES = %w[pending installed failed].freeze
    SCOPES = %w[website portal].freeze
    SITE_SETTING_KEYS = {
      "website" => "frontend.active_website_template",
      "portal" => "frontend.active_portal_template"
    }.freeze

    validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
    validates :name, presence: true
    validates :version, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :scopes_must_be_valid

    scope :installed, -> { where(status: "installed") }

    def installed?
      status == "installed"
    end

    def supports_scope?(scope)
      scopes.include?(scope.to_s)
    end

    def self.active_key_for(scope)
      SiteSetting.get(SITE_SETTING_KEYS.fetch(scope.to_s))
    end

    def self.active_for(scope)
      key = active_key_for(scope)
      return if key.blank?

      installed.find_by(key: key)
    end

    private

    def scopes_must_be_valid
      Array(scopes).each do |scope|
        errors.add(:scopes, "contains invalid scope: #{scope}") unless SCOPES.include?(scope.to_s)
      end
    end
  end
end
