# frozen_string_literal: true

module Identity
  class DataExportRegistry
    Entry = Data.define(:key, :contributor)

    KEY_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/

    def initialize
      @entries = {}
      @frozen = false
    end

    def register(key:, contributor:)
      raise FrozenError, "data_export_registry_frozen" if frozen?

      normalized_key = key.to_s
      raise ArgumentError, "data_export_contributor_key_invalid" unless normalized_key.match?(KEY_PATTERN)
      raise ArgumentError, "data_export_contributor_duplicate" if @entries.key?(normalized_key)
      raise ArgumentError, "data_export_contributor_contract_invalid" unless contributor.respond_to?(:call)

      entry = Entry.new(key: normalized_key.freeze, contributor:)
      @entries[normalized_key] = entry
      entry
    end

    def entries
      @entries.values
    end

    def freeze!
      @entries.freeze
      @frozen = true
      self
    end

    def frozen?
      @frozen
    end
  end
end
