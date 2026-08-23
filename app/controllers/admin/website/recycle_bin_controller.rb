# frozen_string_literal: true

module Admin
  module Website
    class RecycleBinController < BaseController
      CONTENT_TYPES = {
        "page" => ::Website::Page,
        "article" => ::Website::Article
      }.freeze

      before_action :require_recovery_access!, only: %i[index show]
      before_action -> { require_permission("website.content.restore") }, only: %i[restore]
      before_action -> { require_permission("website.content.purge") }, only: %i[authorize_purge purge]
      before_action :set_content, except: %i[index]
      before_action :require_content_read!, except: %i[index]
      before_action :require_content_edit!, only: %i[restore]

      def index
        rows = CONTENT_TYPES.filter_map do |type, model|
          next unless current_user.permission?(read_permission(type))

          model.discarded_content.includes(:discarded_by).map do |content|
            serialize_row(type, content)
          end
        end.flatten.sort_by { |row| row.fetch(:discarded_at_sort) }.reverse

        render inertia: "Admin/Website/Recovery/Index", props: {
          title: t("mcweb.admin.website.recovery.title"),
          rows: rows.map { |row| row.except(:discarded_at_sort) },
          pagesUrl: current_user.permission?("website.pages.read") ? admin_website_pages_path : nil,
          articlesUrl: current_user.permission?("website.articles.read") ? admin_website_articles_path : nil
        }
      end

      def show
        restore_snapshot = latest_discard_snapshot
        restore_validation = ::Website::RestoreValidator.call(
          content: @content,
          snapshot: restore_snapshot
        )
        purge_validation = ::Website::PurgeEligibility.call(content: @content)

        render inertia: "Admin/Website/Recovery/Show", props: {
          title: t("mcweb.admin.website.recovery.detail_title"),
          content: serialize_detail,
          restoreBlockers: restore_validation.value.fetch(:blockers),
          purgeBlockers: purge_validation.value.fetch(:blockers),
          paths: {
            index: admin_website_recycle_bin_path,
            restore: admin_website_restore_recycle_bin_item_path(params[:content_type], @content.public_id),
            authorizePurge: admin_website_authorize_purge_recycle_bin_item_path(params[:content_type], @content.public_id),
            purge: admin_website_purge_recycle_bin_item_path(params[:content_type], @content.public_id),
            revisions: revisions_path
          },
          permissions: {
            restore: current_user.permission?("website.content.restore") &&
              current_user.permission?(edit_permission(params[:content_type])) && @content.discarded?,
            purge: current_user.permission?("website.content.purge") && @content.discarded?
          }
        }
      end

      def restore
        result = ::Website::RestoreContent.call(
          content: @content,
          actor: current_user,
          reason: params[:reason],
          confirmation: params[:confirmation],
          expected_lock_version: params[:lock_version],
          idempotency_key: params[:request_id]
        )
        if result.success?
          redirect_to edit_path, notice: t("mcweb.admin.website.recovery.restored")
        else
          redirect_to admin_website_recycle_bin_item_path(params[:content_type], @content.public_id),
                      alert: service_error_message(result)
        end
      end

      def authorize_purge
        result = ::Website::PurgeAuthorization.call(
          actor: current_user,
          content: @content,
          reason: params[:reason],
          request_id: params[:request_id],
          password: params[:password],
          code: params[:code]
        )
        return render_mutation_error(result) if result.failure?

        value = result.value
        response.set_header("Cache-Control", "private, no-store")
        render json: {
          authorization_token: value.fetch(:authorization_token),
          confirmation: value.fetch(:confirmation),
          request_id: value.fetch(:request_id),
          expires_in: value.fetch(:expires_in),
          preview_items: purge_preview_items
        }
      end

      def purge
        result = ::Website::FinalPurge.call(
          content: @content,
          actor: current_user,
          reason: params[:reason],
          confirmation: params[:confirmation],
          expected_lock_version: @content.lock_version,
          idempotency_key: params[:request_id],
          authorization_token: params[:authorization_token]
        )
        return render_mutation_error(result) if result.failure?

        response.set_header("Cache-Control", "private, no-store")
        render json: {
          redirect_url: admin_website_recycle_bin_path,
          message: t("mcweb.admin.website.recovery.purged")
        }
      end

      private

      def require_recovery_access!
        return if current_user.permission?("website.content.restore") ||
          current_user.permission?("website.content.purge")

        require_permission("website.content.restore")
      end

      def set_content
        model = CONTENT_TYPES[params[:content_type].to_s]
        raise ActiveRecord::RecordNotFound unless model

        @content = model.with_lifecycle.find_by!(public_id: params[:id])
        valid_state = @content.discarded? || @content.purged?
        valid_state ||= action_name == "restore" && @content.active_content?
        raise ActiveRecord::RecordNotFound unless valid_state
      end

      def require_content_read!
        require_permission(read_permission(params[:content_type]))
      end

      def require_content_edit!
        require_permission(edit_permission(params[:content_type]))
      end

      def read_permission(type)
        type.to_s == "page" ? "website.pages.read" : "website.articles.read"
      end

      def edit_permission(type)
        type.to_s == "page" ? "website.pages.edit" : "website.articles.edit"
      end

      def serialize_row(type, content)
        {
          id: content.public_id,
          type: type,
          type_label: t("mcweb.admin.website.recovery.types.#{type}"),
          title: content.title,
          slug: content.slug,
          discarded_by: content.discarded_by&.username,
          discarded_at: l(content.discarded_at, format: :long),
          discarded_at_sort: content.discarded_at,
          purge_at: l(content.purge_at, format: :long),
          reason: content.discard_reason,
          url: admin_website_recycle_bin_item_path(type, content.public_id)
        }
      end

      def serialize_detail
        type = params[:content_type].to_s
        {
          id: @content.public_id,
          type: type,
          type_label: t("mcweb.admin.website.recovery.types.#{type}"),
          title: @content.title,
          slug: @content.slug,
          status: @content.purged? ? "purged" : "discarded",
          lock_version: @content.lock_version,
          discarded_by: @content.discarded_by&.username,
          discarded_at: @content.discarded_at && l(@content.discarded_at, format: :long),
          discard_reason: @content.discard_reason,
          purge_at: @content.purge_at && l(@content.purge_at, format: :long),
          revision_count: @content.revisions.count,
          confirmation: @content.title
        }
      end

      def latest_discard_snapshot
        @content.revisions.where(event_type: "discard").ordered.first&.snapshot || {}
      end

      def revisions_path
        if @content.is_a?(::Website::Page)
          admin_website_page_revisions_path(@content)
        else
          admin_website_article_revisions_path(@content)
        end
      end

      def edit_path
        if @content.is_a?(::Website::Page)
          edit_admin_website_page_path(@content)
        else
          edit_admin_website_article_path(@content)
        end
      end

      def purge_preview_items
        [
          { label: t("mcweb.admin.website.recovery.type"), value: t("mcweb.admin.website.recovery.types.#{params[:content_type]}") },
          { label: t("mcweb.admin.website.recovery.content_title"), value: @content.title },
          { label: t("mcweb.admin.website.recovery.slug"), value: @content.slug },
          { label: t("mcweb.admin.website.recovery.purge_deadline"), value: l(@content.purge_at, format: :long) }
        ]
      end

      def render_mutation_error(result)
        response.set_header("Cache-Control", "private, no-store")
        render json: { error: service_error_message(result) }, status: service_error_status(result)
      end
    end
  end
end
