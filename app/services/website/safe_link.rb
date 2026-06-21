# frozen_string_literal: true

module Website
  module SafeLink
    module_function

    def sanitize_href(url)
      location = url.to_s.strip
      return nil if location.blank?
      return nil if location.match?(/\A(javascript:|data:|vbscript:)/i)
      return nil if location.start_with?("//")
      return location if location.match?(/\Ahttps?:\/\//i)
      return location if location.start_with?("/")

      nil
    end
  end
end
