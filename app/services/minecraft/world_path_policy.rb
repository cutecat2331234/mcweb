# frozen_string_literal: true

module Minecraft
  class WorldPathPolicy
    MAX_PATH_BYTES = 1_024
    MAX_COMPONENT_BYTES = 255
    MAX_DEPTH = 64
    RESERVED_NAMES = %w[CON PRN AUX NUL CLOCK$ CONIN$ CONOUT$].freeze
    RESERVED_PATTERN = /\A(?:COM|LPT)[1-9](?:\..*)?\z/i

    class << self
      def call(value)
        path = value.to_s
        return failure(:world_relative_path_required) if path.blank?
        return failure(:world_relative_path_invalid) unless path.valid_encoding?
        return failure(:world_relative_path_invalid) unless path.ascii_only?
        return failure(:world_relative_path_invalid) unless path == path.strip
        return failure(:world_relative_path_invalid) if path.bytesize > MAX_PATH_BYTES
        return failure(:world_relative_path_invalid) if path.start_with?("/", "//", "\\")
        return failure(:world_relative_path_invalid) if path.include?("\\") || path.include?(":")
        return failure(:world_relative_path_invalid) if path.match?(/[\x00-\x1f\x7f]/)

        components = path.split("/", -1)
        return failure(:world_relative_path_invalid) if components.length > MAX_DEPTH
        return failure(:world_relative_path_invalid) if components.any? { |part| invalid_component?(part) }

        ServiceResult.success(path: components.join("/"))
      end

      private

      def invalid_component?(component)
        return true if component.blank? || component.in?(%w[. ..])
        return true if component.bytesize > MAX_COMPONENT_BYTES
        return true if component.end_with?(".", " ")
        return true if component.match?(/[<>"|?*]/)

        basename = component.split(".", 2).first.to_s.upcase
        RESERVED_NAMES.include?(basename) || component.match?(RESERVED_PATTERN)
      end

      def failure(code)
        ServiceResult.failure(error: code, code: code)
      end
    end
  end
end
