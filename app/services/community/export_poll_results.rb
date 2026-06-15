# frozen_string_literal: true

module Community
  class ExportPollResults < ApplicationService
    def initialize(poll:)
      @poll = poll
    end

    def call
      lines = [ "选项,票数,投票用户" ]
      @poll.options.each_with_index do |label, index|
        voters = @poll.votes.where(option_index: index).includes(:user).map { |vote| vote.user.username }
        voter_cell = @poll.anonymous? ? "（匿名）" : voters.join("; ")
        lines << [ escape_csv(label), voters.size, escape_csv(voter_cell) ].join(",")
      end
      lines << ""
      lines << "问题,#{escape_csv(@poll.question)}"
      lines << "总票数,#{@poll.votes.count}"
      lines << "关闭时间,#{@poll.closes_at&.iso8601}"

      ServiceResult.success(csv: lines.join("\n"))
    end

    private

    def escape_csv(value)
      text = value.to_s
      return text unless text.include?(",") || text.include?('"') || text.include?("\n")

      "\"#{text.gsub('"', '""')}\""
    end
  end
end
