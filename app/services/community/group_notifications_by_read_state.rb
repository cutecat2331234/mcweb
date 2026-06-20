# frozen_string_literal: true

module Community
  class GroupNotificationsByReadState
    def self.call(groups)
      new(groups).sections
    end

    def initialize(groups)
      @groups = Array(groups)
    end

    def sections
      unread = @groups.reject { |group| group[:read] }
      read = @groups.select { |group| group[:read] }

      sections = []
      if unread.any?
        sections << read_state_section("unread", unread, default_expanded: true)
      end
      if read.any?
        sections << read_state_section("read", read, default_expanded: false)
      end
      sections
    end

  private

    def read_state_section(key, groups, default_expanded:)
      {
        key: key,
        label: I18n.t("mcweb.forum.notification_read_state.#{key}"),
        count: groups.size,
        groups: groups,
        timeline_sections: GroupNotificationTimeline.call(groups),
        default_expanded: default_expanded
      }
    end
  end
end
