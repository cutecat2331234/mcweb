# frozen_string_literal: true

module Community
  module ReportMutationKey
    MAX_LENGTH = 128
    FORMAT = /\A[a-zA-Z0-9_.:-]{8,128}\z/

    module_function

    def normalize(value)
      key = value.to_s.strip
      key if key.length <= MAX_LENGTH && key.match?(FORMAT)
    end

    def digest(value)
      Digest::SHA256.hexdigest(value)
    end
  end
end
