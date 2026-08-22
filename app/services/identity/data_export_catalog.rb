# frozen_string_literal: true

require Rails.root.join("lib/mcweb/identity_data_export_registrar_config")

module Identity
  class DataExportCatalog
    class << self
      def entries
        ensure_finalized!
        registry.entries
      end

      def finalize!
        @registry ||= build_registry
        @boot_finalized = true
        @registry
      end

      def registry_frozen?
        @boot_finalized == true && @registry&.frozen? == true
      end

      private

      def registry
        ensure_finalized!
        @registry
      end

      def ensure_finalized!
        return if @boot_finalized == true

        raise FrozenError, "data_export_registry_not_boot_finalized"
      end

      def build_registry
        candidate = DataExportRegistry.new
        CoreDataExportContributors.register(candidate)
        configured_registrars.each { |registrar| registrar.call(candidate) }
        candidate.freeze!
      end

      def configured_registrars
        Mcweb::IdentityDataExportRegistrarConfig.freeze_and_fetch!(
          Rails.application.config.x
        )
      end
    end
  end
end
