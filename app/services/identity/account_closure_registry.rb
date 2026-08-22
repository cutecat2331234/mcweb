# frozen_string_literal: true

module Identity
  class AccountClosureRegistry
    Entry = Data.define(:key, :contributor)

    KEY_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
    REQUIRED_METHODS = %i[preflight execute compensate].freeze

    def initialize
      @entries = {}
      @frozen = false
    end

    def register(key:, contributor:)
      raise FrozenError, "account_closure_registry_frozen" if frozen?

      normalized_key = key.to_s
      unless normalized_key.match?(KEY_PATTERN)
        raise ArgumentError, "account_closure_contributor_key_invalid"
      end
      if @entries.key?(normalized_key)
        raise ArgumentError, "account_closure_contributor_duplicate"
      end
      unless REQUIRED_METHODS.all? { |method_name| contributor.respond_to?(method_name) }
        raise ArgumentError, "account_closure_contributor_contract_invalid"
      end

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
