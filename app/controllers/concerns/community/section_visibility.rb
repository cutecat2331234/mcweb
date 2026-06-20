# frozen_string_literal: true

module Community
  module SectionVisibility
    extend ActiveSupport::Concern

    private

    def section_visible?(section, user: current_user)
      section.visible_to?(user)
    end

    def ensure_section_visible!(section)
      return if section_visible?(section)

      if logged_in?
        raise ActiveRecord::RecordNotFound
      else
        store_return_location
        redirect_to identity_sign_in_path, alert: t("mcweb.flash.sign_in_required")
      end
    end

    def filter_login_required_sections(sections)
      return sections if logged_in?

      sections.reject(&:login_required?)
    end

    def apply_login_required_topic_scope(scope)
      scope.merge(Community::Topic.accessible_by(current_user))
    end

    def apply_login_required_post_scope(scope)
      return scope if logged_in?

      scope.joins(topic: :section).where(forum_sections: { login_required: false })
    end
  end
end
