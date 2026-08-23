# frozen_string_literal: true

module Community
  module ReportAffectedUserResolver
    module_function

    def call(reportable)
      user_id = case reportable
      when Community::Topic, Community::Post, Community::Message, Commerce::Review
        reportable.user_id
      when Community::ProfilePost, Community::ProfilePostComment
        reportable.user_id
      when User
        reportable.id
      end
      return unless user_id

      User.find_by(id: user_id)
    end
  end
end
