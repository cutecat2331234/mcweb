# frozen_string_literal: true

module Identity
  module CoreDataExportContributors
    module_function

    def register(registry)
      registry.register(
        key: "identity.profile",
        contributor: DataExporting::ProfileContributor
      )
      registry.register(
        key: "identity.notifications",
        contributor: DataExporting::NotificationsContributor
      )
      registry.register(
        key: "community.content",
        contributor: DataExporting::CommunityContentContributor
      )
      registry.register(
        key: "community.uploads",
        contributor: DataExporting::CommunityUploadsContributor
      )
      registry.register(
        key: "commerce.account",
        contributor: DataExporting::CommerceAccountContributor
      )
    end
  end
end
