module Website
  class Theme < ApplicationRecord
    has_many :pages, class_name: "Website::Page", foreign_key: :website_theme_id, dependent: :nullify

    validates :name, presence: true
    validates :key, presence: true, uniqueness: true

    scope :active_themes, -> { where(active: true) }

    def self.current
      active_themes.first
    end

    def activate!
      transaction do
        self.class.update_all(active: false)
        update!(active: true)
      end
    end
  end
end
