# frozen_string_literal: true

module Minecraft
  module SyncFilePath
    ALLOWED_ROOTS = [
      Rails.root.join("storage"),
      Rails.root.join("public")
    ].freeze

    module_function

    def resolve(path)
      return nil if path.blank?

      full = Pathname.new(path.to_s)
      full = Rails.root.join(full) unless full.absolute?
      full = full.cleanpath

      return nil unless full.file?
      return nil unless allowed?(full)

      full
    end

    def allowed?(full)
      ALLOWED_ROOTS.any? { |root| Frontend::PathContainment.within_root?(full, root) }
    end
  end
end
