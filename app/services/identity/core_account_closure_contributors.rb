# frozen_string_literal: true

module Identity
  module CoreAccountClosureContributors
    module_function

    def register(registry)
      registry.register(
        key: "identity.authored_content",
        contributor: AccountClosure::AuthoredContentContributor
      )
    end
  end
end
