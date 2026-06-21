# frozen_string_literal: true

module Minecraft
  module HmacReplayGuard
    class << self
      attr_writer :cache_store

      def cache_store
        @cache_store || Rails.cache
      end
    end

    module_function

    def replayed?(scope:, signature:, expires_in: 5.minutes)
      return false if signature.blank?

      key = "hmac_replay:#{scope}:#{signature}"
      !cache_store.write(key, true, expires_in: expires_in, unless_exist: true)
    end
  end
end
