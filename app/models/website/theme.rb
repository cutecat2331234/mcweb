module Website
  class Theme < ApplicationRecord
    has_many :pages, class_name: "Website::Page", foreign_key: :website_theme_id, dependent: :nullify
    has_many :revisions,
      class_name: "Website::ThemeRevision",
      foreign_key: :website_theme_id,
      inverse_of: :theme,
      dependent: :restrict_with_error

    validates :name, presence: true
    validates :key, presence: true, uniqueness: true
    validate :tokens_must_be_an_object

    scope :active_themes, -> { where(active: true) }

    def self.current
      active_themes.first
    end

    def activate!(actor: nil, expected_lock_version: lock_version)
      result = Website::MutateTheme.call(
        operation: :activate,
        theme: self,
        actor: actor,
        expected_lock_version: expected_lock_version
      )
      return reload if result.success?

      raise Website::LifecycleError, result.code.presence || "website_theme_activation_failed"
    end

    private

    def tokens_must_be_an_object
      return if tokens.is_a?(Hash)

      errors.add(:tokens, I18n.t("mcweb.services.errors.website_theme_tokens_invalid"))
    end
  end
end
