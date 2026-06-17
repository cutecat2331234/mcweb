# frozen_string_literal: true

module Community
  class HighlightSearchText < ApplicationService
    def initialize(text:, query:)
      @text = text.to_s
      @query = query.to_s.strip
    end

    def call
      return ServiceResult.success(html: ERB::Util.html_escape(@text)) if @query.blank?

      terms = @query.split(/\s+/).map { |t| t.gsub(/[^\p{L}\p{N}_]/u, "") }.reject(&:blank?).uniq
      return ServiceResult.success(html: ERB::Util.html_escape(@text)) if terms.empty?

      html = ERB::Util.html_escape(@text)
      terms.each do |term|
        pattern = Regexp.new(Regexp.escape(term), Regexp::IGNORECASE)
        html = html.gsub(pattern) { |match| "<mark>#{match}</mark>" }
      end
      ServiceResult.success(html: html.html_safe)
    end
  end
end
