# frozen_string_literal: true

require Rails.root.join("lib/mcweb/identity_account_closure_registrar_config")

module Identity
  class AccountClosureCatalog
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

        raise FrozenError, "account_closure_registry_not_boot_finalized"
      end

      def build_registry
        candidate = AccountClosureRegistry.new
        CoreAccountClosureContributors.register(candidate)
        configured_registrars.each { |registrar| registrar.call(candidate) }
        candidate.freeze!
      end

      def configured_registrars
        Mcweb::IdentityAccountClosureRegistrarConfig.freeze_and_fetch!(
          Rails.application.config.x
        )
      end
    end
  end
end
