# frozen_string_literal: true

module Mcweb
  # I18n backend that serves DB-backed phrase overrides (Community::PhraseOverride)
  # as the first link in an I18n::Backend::Chain. Returns nil for keys without an
  # override so the chain falls through to the YAML backend. The full override map
  # is memoized in-process with a short TTL, so translation lookups never hit the
  # database per call.
  class PhraseBackend
    include ::I18n::Backend::Base

    RELOAD_INTERVAL = 30 # seconds

    def available_locales
      cached_map.keys.map(&:to_sym)
    rescue StandardError
      []
    end

    def store_translations(_locale, _data, _options = {})
      # Read-only override backend.
    end

    def reload!
      @cached_map = nil
      @loaded_at = nil
    end

    protected

    def lookup(locale, key, scope = [], options = {})
      overrides = cached_map[locale.to_s]
      return nil if overrides.nil? || overrides.empty?

      parts = ::I18n.normalize_keys(locale, key, scope, options[:separator])
      flat_key = parts[1..].join(".")
      overrides[flat_key]
    rescue StandardError
      nil
    end

    private

    def cached_map
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if @cached_map.nil? || @loaded_at.nil? || (now - @loaded_at) > RELOAD_INTERVAL
        @cached_map = Community::PhraseOverride.map
        @loaded_at = now
      end
      @cached_map
    end
  end
end
