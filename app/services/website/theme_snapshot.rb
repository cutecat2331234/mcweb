# frozen_string_literal: true

module Website
  class ThemeSnapshot < ApplicationService
    SNAPSHOT_KEYS = %w[name key tokens active].freeze

    def initialize(theme: nil, snapshot: nil)
      @theme = theme
      @snapshot = snapshot
    end

    def call
      source = @theme ? attributes_from_theme : @snapshot.to_h.stringify_keys
      {
        "name" => source.fetch("name").to_s,
        "key" => source.fetch("key").to_s,
        "tokens" => canonical_tokens(source["tokens"]),
        "active" => source["active"] == true
      }
    end

    private

    def attributes_from_theme
      {
        "name" => @theme.name,
        "key" => @theme.key,
        "tokens" => @theme.tokens,
        "active" => @theme.active?
      }
    end

    def canonical_tokens(value)
      raise Website::LifecycleError, "website_theme_snapshot_invalid" unless value.is_a?(Hash)

      canonical_json(value)
    end

    def canonical_json(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), result|
          result[key.to_s] = canonical_json(nested)
        end.sort.to_h
      when Array
        value.map { |nested| canonical_json(nested) }
      when String, Integer, Float, TrueClass, FalseClass, NilClass
        value
      else
        JSON.parse(JSON.generate(value))
      end
    end
  end
end
