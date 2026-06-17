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
        sections << read_state_section("unread", "未读", unread, default_expanded: true)
      end
      if read.any?
        sections << read_state_section("read", "已读", read, default_expanded: false)
      end
      sections
    end

  private

    def read_state_section(key, label, groups, default_expanded:)
      {
        key: key,
        label: label,
        count: groups.size,
        groups: groups,
        timeline_sections: GroupNotificationTimeline.call(groups),
        default_expanded: default_expanded
      }
    end
  end
end
