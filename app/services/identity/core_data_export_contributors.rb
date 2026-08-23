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
        key: "community.report_cases",
        contributor: Community::ReportIdentityLifecycle::DataExportContributor
      )
      registry.register(
        key: "commerce.account",
        contributor: DataExporting::CommerceAccountContributor
      )
      registry.register(
        key: "minecraft.accounts",
        contributor: Minecraft::IdentityLifecycle::DataExportContributor
      )
      registry.register(
        key: "security.evidence_attachments",
        contributor: SecureEvidence::IdentityLifecycle::DataExportContributor
      )
    end
  end
end
