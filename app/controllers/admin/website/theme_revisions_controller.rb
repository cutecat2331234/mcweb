# frozen_string_literal: true

module Admin
  module Website
    class ThemeRevisionsController < BaseController
      PER_PAGE = 25

      before_action -> { require_permission("website.pages.read") }
      before_action -> { require_permission("website.pages.edit") }, only: %i[restore]
      before_action -> { require_permission("website.content.restore") }, only: %i[restore]
      before_action :set_theme
      before_action :set_revision, only: %i[show restore]

      def index
        anchor = history_anchor
        scope = @theme.revisions
          .where("revision_number <= ?", anchor)
          .includes(:actor)
          .ordered
        @pagy, revisions = pagy(:offset, scope, limit: PER_PAGE)

        render inertia: "Admin/Website/ThemeRevisions/Index", props: {
          title: t("mcweb.admin.website.theme_version_governance.history_title"),
          theme: theme_props,
          revisions: revisions.map { |revision| revision_summary(revision) },
          pagination: pagy_props(@pagy).merge(anchor: anchor, pageSize: PER_PAGE),
          backUrl: admin_website_theme_path(@theme),
          copy: index_copy
        }
      end

      def show
        previous = @theme.revisions
          .where("revision_number < ?", @revision.revision_number)
          .order(revision_number: :desc, id: :desc)
          .first
        snapshot = ::Website::ThemeSnapshot.call(snapshot: @revision.snapshot)
        difference = previous ? ::Website::ThemeRevisionDiff.call(
          before_snapshot: previous.snapshot,
          after_snapshot: snapshot
        ) : []

        render inertia: "Admin/Website/ThemeRevisions/Show", props: {
          title: t("mcweb.admin.website.theme_version_governance.detail_title"),
          theme: theme_props,
          revision: revision_summary(@revision).merge(
            snapshot: snapshot,
            difference: difference,
            predecessorRevisionNumber: previous&.revision_number,
            sourceRevisionNumber: @revision.source_revision&.revision_number,
            restoreUrl: restore_admin_website_theme_revision_path(
              @theme,
              @revision.revision_number
            )
          ),
          canRestore: can_restore?,
          backUrl: admin_website_theme_revisions_path(@theme),
          copy: show_copy
        }
      end

      def restore
        result = ::Website::RestoreThemeRevision.call(
          theme: @theme,
          revision: @revision,
          actor: current_user,
          reason: params[:reason],
          confirmation: params[:confirmation],
          expected_lock_version: params[:lock_version],
          idempotency_key: params[:request_id]
        )
        if result.success?
          successor = result.value.fetch(:revision)
          redirect_to admin_website_theme_revision_path(@theme, successor.revision_number),
            notice: t("mcweb.admin.website.theme_version_governance.restored")
        else
          redirect_to admin_website_theme_revision_path(@theme, @revision.revision_number),
            alert: service_error_message(result)
        end
      end

      private

      def set_theme
        @theme = ::Website::Theme.find(params[:theme_id])
      end

      def set_revision
        @revision = @theme.revisions
          .includes(:actor, :source_revision)
          .find_by!(revision_number: params[:revision_number])
      end

      def history_anchor
        latest = @theme.revisions.maximum(:revision_number).to_i
        requested = Integer(params[:anchor], exception: false)
        return latest unless requested&.positive?

        [ requested, latest ].min
      end

      def revision_summary(revision)
        {
          revisionNumber: revision.revision_number,
          eventType: revision.event_type,
          eventLabel: t(
            "mcweb.admin.website.theme_version_governance.events.#{revision.event_type}"
          ),
          actor: revision.actor&.username,
          reason: revision.reason,
          createdAt: l(revision.created_at, format: :long),
          url: admin_website_theme_revision_path(@theme, revision.revision_number)
        }
      end

      def theme_props
        {
          name: @theme.name,
          key: @theme.key,
          active: @theme.active?,
          lockVersion: @theme.lock_version
        }
      end

      def can_restore?
        current_user.permission?("website.pages.edit") &&
          current_user.permission?("website.content.restore")
      end

      def index_copy
        copy_for(%i[
          back revision event actor reason created_at view empty range
        ])
      end

      def show_copy
        copy_for(%i[
          back revision event actor reason created_at source_revision predecessor
          snapshot name key tokens differences path before after no_differences missing
          active inactive restore_title restore_warning restore_reason
          restore_confirmation restore_confirmation_hint restore_action
        ])
      end

      def copy_for(keys)
        keys.index_with do |key|
          t("mcweb.admin.website.theme_version_governance.copy.#{key}")
        end
      end
    end
  end
end
