# frozen_string_literal: true

module Community
  module WarningRestrictionsSerializable
    extend ActiveSupport::Concern

    private

    def warning_restrictions_props
      return { post: nil, link: nil, pm: nil } unless logged_in?

      %i[post link pm].index_with do |action|
        result = Community::CheckWarningRestrictions.call(user: current_user, action: action)
        result.failure? ? result.error : nil
      end
    end
  end
end
