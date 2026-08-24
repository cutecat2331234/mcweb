# frozen_string_literal: true

module Admin
  module Website
    class PagesController < BaseController
      include NestedLocaleParams

      before_action -> { require_permission("website.pages.read") }
      before_action -> { require_permission("website.pages.edit") },
                    only: %i[new create edit update discard_form discard archive]
      before_action -> { require_permission("website.pages.publish") }, only: %i[publish schedule archive]
      before_action :set_page,
                    only: %i[show edit update discard_form discard publish schedule archive preview]

      def index
        pages = ::Website::Page.order(updated_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.website.pages.title"),
          columns: [
            admin_column(:title, t("mcweb.admin.website.pages.col_title"), link: true),
            admin_column(:slug, t("mcweb.admin.website.pages.col_slug")),
            admin_column(:status, t("mcweb.admin.common.status")),
            admin_column(:updated, t("mcweb.admin.common.updated"))
          ],
          rows: pages.map do |page|
            admin_row(
              title: page.title,
              slug: page.slug,
              status: content_status_label(page.status),
              updated: l(page.updated_at, format: :short),
              url: admin_website_page_path(page)
            )
          end,
          actions: index_actions
        }
      end

      def show
        preview_url = preview_admin_website_page_path(@page)
        render inertia: "Admin/Generic/Show", props: {
          title: @page.title,
          subtitle: @page.slug,
          fields: [
            { label: t("mcweb.admin.website.pages.field_type"), value: page_type_label(@page.page_type) },
            { label: t("mcweb.admin.common.status"), value: content_status_label(@page.status) },
            { label: t("mcweb.admin.common.updated"), value: l(@page.updated_at, format: :long) },
            { label: "SEO", value: @page.seo.to_json.truncate(120) }
          ],
          backUrl: admin_website_pages_path,
          actions: show_actions(preview_url)
        }
      end

      def new
        render inertia: "Admin/Website/Pages/Form", props: form_props(::Website::Page.new)
      end

      def create
        page = ::Website::Page.new(page_params)
        page.author = current_user

        if page.save
          redirect_to edit_admin_website_page_path(page), notice: t("mcweb.flash.created", resource: t("mcweb.resources.page"))
        else
          render inertia: "Admin/Website/Pages/Form", props: form_props(page), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Website/Pages/Form", props: form_props(@page)
      end

      def update
        result = ::Website::ContentUpdate.call(
          content: @page,
          attributes: page_params.except(:lock_version),
          actor: current_user,
          expected_lock_version: page_params[:lock_version],
          request_id: params[:request_id]
        )
        if result.success?
          redirect_to admin_website_page_path(@page),
                      notice: t("mcweb.flash.updated", resource: t("mcweb.resources.page"))
        else
          redirect_to edit_admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      def discard_form
        render inertia: "Admin/Website/ContentDiscard", props: discard_form_props
      end

      def discard
        result = ::Website::DiscardContent.call(
          content: @page,
          actor: current_user,
          reason: params[:reason],
          confirmation: params[:confirmation],
          expected_lock_version: params[:lock_version],
          idempotency_key: params[:request_id],
          replacement_page_public_id: params[:replacement_page_public_id]
        )
        if result.success?
          redirect_to admin_website_recycle_bin_path,
                      notice: t("mcweb.admin.website.recovery.discarded")
        else
          redirect_to discard_form_admin_website_page_path(@page),
                      alert: service_error_message(result)
        end
      end

      def publish
        result = ::Website::PagePublisher.call(
          page: @page,
          actor: current_user,
          expected_lock_version: params[:lock_version],
          request_id: params[:request_id]
        )
        if result.success?
          redirect_to admin_website_page_path(@page), notice: t("mcweb.admin.website.published", default: "Published")
        else
          redirect_to admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      def schedule
        publish_at = parse_schedule_time(params[:publish_at])
        unless publish_at&.future?
          redirect_to admin_website_page_path(@page),
                      alert: t("mcweb.admin.website.invalid_schedule", default: "Choose a future publish date and time")
          return
        end

        result = ::Website::PagePublisher.call(
          page: @page,
          publish_at: publish_at,
          actor: current_user,
          expected_lock_version: params[:lock_version],
          request_id: params[:request_id]
        )
        if result.success?
          redirect_to admin_website_page_path(@page), notice: t("mcweb.admin.website.scheduled", default: "Scheduled")
        else
          redirect_to admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      def archive
        result = ::Website::ArchiveContent.call(
          content: @page,
          actor: current_user,
          expected_lock_version: params[:lock_version],
          request_id: params[:request_id]
        )
        if result.success?
          redirect_to admin_website_page_path(@page),
                      notice: t("mcweb.admin.website.recovery.archived")
        else
          redirect_to admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      def preview
        blocks_result = ::Website::SerializePageBlocks.call(page: @page)
        seo_result = ::Website::ResolveSeo.call(record: @page)

        ::Frontend::WebsiteRenderer.preview(
          controller: self,
          component: "Website/Pages/Show",
          props: {
          page: { title: @page.title, slug: @page.slug },
          blocks: blocks_result.value,
          seo: seo_result.value,
          preview_context: {
            return_url: admin_website_page_path(@page),
            edit_url: edit_admin_website_page_path(@page),
            label: @page.title,
            mode_label: t("mcweb.admin.website.preview", default: "Preview")
          }
          }
        )
      end

      private

      def set_page
        scope = action_name == "discard" ? ::Website::Page.with_lifecycle : ::Website::Page.all
        @page = scope.find_by!(public_id: params[:id])
      end

      def page_params
        permitted = params.require(:page).permit(
          :title, :slug, :page_type, :website_theme_id, :lock_version,
          seo: {}
        )
        permitted[:seo] = permitted[:seo].to_unsafe_h if permitted[:seo].is_a?(ActionController::Parameters)
        merge_nested_translations!(permitted, :page)
        permitted
      end

      def parse_schedule_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def form_props(page)
        {
          title: page.persisted? ? t("mcweb.admin.website.pages.edit") : t("mcweb.admin.website.pages.new"),
          page: serialize_page_form(page),
          blocks: page.persisted? ? page.blocks.unscope(:order).order(:position).map { |b| serialize_block(b) } : [],
          pageTypeOptions: %w[custom home landing].map { |value| { value:, label: page_type_label(value) } },
          statusOptions: ::Website::Page.statuses.keys.map { |value| { value:, label: content_status_label(value) } },
          themeOptions: ::Website::Theme.order(:name).map { |t| { value: t.id, label: t.name } },
          locales: %w[en zh-CN],
          submitUrl: page.persisted? ? admin_website_page_path(page) : admin_website_pages_path,
          publishUrl: page.persisted? ? publish_admin_website_page_path(page) : nil,
          scheduleUrl: page.persisted? ? schedule_admin_website_page_path(page) : nil,
          previewUrl: page.persisted? ? preview_admin_website_page_path(page) : nil,
          blocksBaseUrl: page.persisted? ? admin_website_page_blocks_path(page) : nil,
          revisionsUrl: page.persisted? ? admin_website_page_revisions_path(page) : nil,
          method: page.persisted? ? "patch" : "post",
          backUrl: page.persisted? ? admin_website_page_path(page) : admin_website_pages_path,
          form_errors: page.errors.to_hash(true),
          canPublish: current_user.permission?("website.pages.publish")
        }
      end

      def serialize_page_form(page)
        {
          title: page.title,
          slug: page.slug,
          page_type: page.page_type.presence || "custom",
          status: page.status.presence || "draft",
          website_theme_id: page.website_theme_id,
          scheduled_at: page.scheduled_at&.strftime("%Y-%m-%dT%H:%M"),
          seo: page.seo.presence || { "title" => "", "description" => "", "og_image" => "" },
          translations: page.translations.presence || {},
          lock_version: page.lock_version
        }
      end

      def page_type_label(value)
        t("mcweb.admin.website.pages.types.#{value}")
      end

      def content_status_label(value)
        t("mcweb.admin.website.statuses.#{value}")
      end

      def serialize_block(block)
        {
          id: block.id,
          block_type: block.block_type,
          position: block.position,
          visible: block.visible,
          settings: block.settings || {}
        }
      end

      def show_actions(preview_url)
        actions = [
          { label: t("mcweb.admin.website.preview", default: "Preview"), href: preview_url, hardNavigation: true },
          { label: t("mcweb.admin.website.revisions.title", default: "Revisions"), href: admin_website_page_revisions_path(@page) }
        ]
        if current_user.permission?("website.pages.edit")
          actions.unshift(label: t("mcweb.admin.ui.edit"), href: edit_admin_website_page_path(@page))
        end
        if current_user.permission?("website.pages.publish")
          actions << {
            label: t("mcweb.admin.website.publish", default: "Publish"),
            href: publish_admin_website_page_path(@page), method: "post",
            data: { lock_version: @page.lock_version, request_id: "website-publish-page-#{SecureRandom.uuid}" }
          }
        end
        if current_user.permission?("website.pages.edit") &&
            current_user.permission?("website.pages.publish")
          actions << {
            label: t("mcweb.admin.website.recovery.archive"),
            href: archive_admin_website_page_path(@page), method: "post",
            data: { lock_version: @page.lock_version, request_id: "website-archive-page-#{SecureRandom.uuid}" },
            confirm: t("mcweb.admin.website.recovery.archive_confirm")
          }
        end
        if current_user.permission?("website.pages.edit")
          actions << {
            label: t("mcweb.admin.website.recovery.discard"),
            href: discard_form_admin_website_page_path(@page)
          }
        end
        actions
      end

      def discard_form_props
        replacements = if @page.page_type == "home" && @page.published?
          ::Website::Page.published.where(page_type: "home").where.not(id: @page.id)
        else
          ::Website::Page.none
        end
        {
          title: t("mcweb.admin.website.recovery.discard_title"),
          content: {
            type: "page", title: @page.title, slug: @page.slug,
            lock_version: @page.lock_version
          },
          submitUrl: discard_admin_website_page_path(@page),
          backUrl: admin_website_page_path(@page),
          replacementRequired: @page.page_type == "home" && @page.published?,
          replacementOptions: replacements.map do |replacement|
            { value: replacement.public_id, label: replacement.title }
          end
        }
      end

      def index_actions
        actions = []
        if current_user.permission?("website.pages.edit")
          actions << { label: t("mcweb.admin.website.pages.new"), href: new_admin_website_page_path }
        end
        if current_user.permission?("website.content.restore") ||
            current_user.permission?("website.content.purge")
          actions << { label: t("mcweb.admin.website.recovery.title"), href: admin_website_recycle_bin_path }
        end
        actions
      end
    end
  end
end
