# frozen_string_literal: true

module Identity
  module CoreAccountClosureContributors
    module_function

    def register(registry)
      registry.register(
        key: "identity.authored_content",
        contributor: AccountClosure::AuthoredContentContributor
      )
      registry.register(
        key: "minecraft.identity_bindings",
        contributor: Minecraft::IdentityLifecycle::AccountClosureContributor
      )
    end
  end
end
