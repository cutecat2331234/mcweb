# frozen_string_literal: true

require Rails.root.join("lib/mcweb/secure_evidence_subject_registrar_config")

module SecureEvidence
  class SubjectCatalog
    class << self
      def entries
        ensure_finalized!
        registry.entries
      end

      def entry_for_key(key)
        ensure_finalized!
        registry.entry_for_key(key)
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

        raise FrozenError, "secure_evidence_subject_registry_not_boot_finalized"
      end

      def build_registry
        candidate = SubjectRegistry.new
        configured_registrars.each { |registrar| registrar.call(candidate) }
        candidate.freeze!
      end

      def configured_registrars
        Mcweb::SecureEvidenceSubjectRegistrarConfig.freeze_and_fetch!(
          Rails.application.config.x
        )
      end
    end
  end
end
