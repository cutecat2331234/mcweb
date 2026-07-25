# frozen_string_literal: true

module Community
  # Canonical read policy for forum sections.
  #
  # Section#visible_to? owns the login-required rule and Section#allowed?
  # owns trust/permission rules. Keeping their composition here gives web,
  # API, and future Action Cable channels one authorization entry point.
  module SectionAccess
    module_function

    def view?(section:, user:)
      section.present? &&
        section.visible_to?(user) &&
        section.allowed?(user, :view)
    end

    def visible_ids(user:)
      candidates = Community::Section.all
      candidates = candidates.where(login_required: false) unless user

      candidates.filter_map { |section| section.id if view?(section: section, user: user) }
    end

    def scope(relation:, user:)
      relation.where(id: visible_ids(user: user))
    end

    def select(sections:, user:)
      sections.select { |section| view?(section: section, user: user) }
    end
  end
end
