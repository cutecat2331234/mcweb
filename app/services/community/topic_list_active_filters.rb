# frozen_string_literal: true

module Community
  class TopicListActiveFilters
    def self.call(filter:, prefixes: [], staff: false)
      new(filter: filter, prefixes: prefixes, staff: staff).chips
    end

    def initialize(filter:, prefixes: [], staff: false)
      @filter = filter.to_s
      @prefixes = prefixes
      @staff = staff
    end

    def chips
      return [] if @filter.blank?

      label = filter_label
      return [] if label.blank?

      [ { param: "filter", label: label, value: @filter } ]
    end

  private

    def filter_label
      if (match = @filter.match(/\Aprefix:(.+)\z/))
        "前缀：#{match[1]}"
      else
        labels.fetch(@filter, nil)
      end
    end

    def labels
      @labels ||= begin
        map = {
          "unsolved" => "未解决",
          "solved" => "已解决",
          "solved_mine" => "我已解决",
          "mine" => "我的主题",
          "participated" => "我参与的",
          "unread" => "未读",
          "no_replies" => "零回复",
          "locked" => "已锁定",
          "unlocked" => "未锁定",
          "pinned" => "已置顶",
          "wiki" => "Wiki 主题",
          "featured" => "精选主题",
          "announcement" => "全站公告",
          "has_poll" => "含投票",
          "assigned" => "已指派",
          "unassigned" => "未指派",
          "assigned_mine" => "指派给我",
          "unlisted" => "未列出",
          "archived" => "已归档"
        }
        @prefixes.each { |prefix| map["prefix:#{prefix}"] = "前缀：#{prefix}" }
        map
      end
    end
  end
end
