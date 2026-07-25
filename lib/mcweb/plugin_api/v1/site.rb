# frozen_string_literal: true

require_relative "result"

module Mcweb
  module PluginApi
    module V1
      class Site
        MAX_SETTING_KEY_LENGTH = 191

        def initialize(capability_auditor: nil)
          @capability_auditor = capability_auditor
          freeze
        end

        def features
          audit("site.features.read")
          Result.success(FeatureFlags.frontend_hash)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def feature(feature_id)
          audit("site.features.read")
          definition = FeatureFlags.definition_for(feature_id)
          unless definition
            return Result.failure(code: "not_found", error: "feature is not defined")
          end

          Result.success(FeatureFlags.enabled?(definition.id))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def setting(key, default: nil)
          audit("site.settings.read")
          key = key.to_s.dup.freeze
          unless key.length.between?(1, MAX_SETTING_KEY_LENGTH)
            return Result.failure(code: "invalid_argument", error: "invalid setting key")
          end

          Result.success(SiteSetting.get(key, default))
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        private

        def audit(capability)
          @capability_auditor&.call(capability)
        end
      end
    end
  end
end
