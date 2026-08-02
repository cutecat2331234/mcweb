# frozen_string_literal: true

module Community
  module SectionVisibility
    extend ActiveSupport::Concern

    private

    def section_visible?(section, user: current_user)
      Community::SectionAccess.view?(section: section, user: user)
    end

    def ensure_section_visible!(section)
      return if section_visible?(section)
      raise ActiveRecord::RecordNotFound unless section.publicly_active?

      if !logged_in? && section.login_required?
        store_return_location
        redirect_to identity_sign_in_path, alert: t("mcweb.flash.sign_in_required")
      else
        raise ActiveRecord::RecordNotFound
      end
    end

    def filter_login_required_sections(sections)
      Community::SectionAccess.select(sections: sections, user: current_user)
    end

    def apply_login_required_topic_scope(scope)
      Community::ForumAccess.topic_scope(relation: scope, user: current_user)
    end

    def apply_login_required_post_scope(scope)
      Community::ForumAccess.post_scope(relation: scope, user: current_user)
    end
  end
end
