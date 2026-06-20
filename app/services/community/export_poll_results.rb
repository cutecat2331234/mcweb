# frozen_string_literal: true

module Community
  class ExportPollResults < ApplicationService
    def initialize(poll:)
      @poll = poll
    end

    def call
      lines = [ I18n.t("mcweb.forum.exports.poll_header") ]
      @poll.options.each_with_index do |label, index|
        voters = @poll.votes.where(option_index: index).includes(:user).map { |vote| vote.user.username }
        voter_cell = @poll.anonymous? ? I18n.t("mcweb.forum.exports.poll_anonymous") : voters.join("; ")
        lines << [ escape_csv(label), voters.size, escape_csv(voter_cell) ].join(",")
      end
      lines << ""
      lines << "#{I18n.t('mcweb.forum.exports.poll_question')},#{escape_csv(@poll.question)}"
      lines << "#{I18n.t('mcweb.forum.exports.poll_total_votes')},#{@poll.votes.count}"
      lines << "#{I18n.t('mcweb.forum.exports.poll_closed_at')},#{@poll.closes_at&.iso8601}"

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
