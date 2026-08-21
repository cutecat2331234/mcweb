# frozen_string_literal: true

require "digest"

module Commerce
  module AuditContentSnapshot
    module_function

    def fields(name, value)
      text = value.to_s
      {
        "#{name}_length" => text.length,
        "#{name}_sha256" => Digest::SHA256.hexdigest(text)
      }
    end
  end
end
