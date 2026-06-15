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
        sections << {
          key: "unread",
          label: "未读",
          count: unread.size,
          groups: unread,
          default_expanded: true
        }
      end
      if read.any?
        sections << {
          key: "read",
          label: "已读",
          count: read.size,
          groups: read,
          default_expanded: false
        }
      end
      sections
    end
  end
end
