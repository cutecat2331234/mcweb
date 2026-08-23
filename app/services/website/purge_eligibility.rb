# frozen_string_literal: true

module Website
  class PurgeEligibility < ApplicationService
    def initialize(content:, at: Time.current)
      @content = content
      @at = at
    end

    def call
      blockers = []
      blockers << "website_purge_not_discarded" unless @content.discarded?
      blockers << "website_purge_retention_pending" if @content.purge_at.nil? || @content.purge_at > @at
      blockers << "website_purge_legal_hold" if active_hold?
      blockers << "website_purge_navigation_reference" if active_navigation_reference?
      blockers << "website_purge_scheduled_content" if scheduled_reference?
      blockers << "website_purge_revision_missing" unless @content.revisions.exists?

      ServiceResult.success(allowed: blockers.empty?, blockers: blockers.uniq)
    end

    private

    def active_hold?
      DataGovernance::RetentionHold.effective.where(
        target_type: @content.class.base_class.name,
        target_id: @content.id
      ).exists?
    end

    def active_navigation_reference?
      paths = if @content.is_a?(Website::Page)
        [ "/#{@content.slug}" ]
      else
        [ "/blog/#{@content.slug}" ]
      end
      direct = @content.is_a?(Website::Page) &&
        Website::NavItem.visible_items.where(website_page_id: @content.id).exists?
      direct || Website::NavItem.visible_items.where(url: paths).exists?
    end

    def scheduled_reference?
      @content.status == "scheduled" || @content.scheduled_at.present?
    end
  end
end
