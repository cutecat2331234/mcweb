# frozen_string_literal: true

class CustomSafeHtml < String
  def self.wrap(content)
    new(content.to_s)
  end
end
