# frozen_string_literal: true

module Admin
  module Website
    class PagesController < BaseController
      before_action -> { require_permission("website.pages.read") }, only: %i[index show]
      before_action -> { require_permission("website.pages.edit") }, only: %i[new create edit update destroy]
      before_action -> { require_permission("website.pages.publish") }, only: %i[publish schedule]
      before_action :set_page, only: %i[show edit update destroy publish schedule]

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
              status: page.status,
              updated: l(page.updated_at, format: :short),
              url: admin_website_page_path(page)
            )
          end,
          actions: [ { label: t("mcweb.admin.website.pages.new"), href: new_admin_website_page_path } ]
        }
      end

      def show
        preview_url = @page.page_type == "home" && @page.published? ? "/" : "/#{@page.slug}"
        render inertia: "Admin/Generic/Show", props: {
          title: @page.title,
          subtitle: @page.slug,
          fields: [
            { label: t("mcweb.admin.website.pages.field_type"), value: @page.page_type },
            { label: t("mcweb.admin.common.status"), value: @page.status },
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
        if @page.update(page_params)
          @page.create_revision!(author: current_user) if @page.published?
          redirect_to admin_website_page_path(@page), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.page"))
        else
          render inertia: "Admin/Website/Pages/Form", props: form_props(@page), status: :unprocessable_entity
        end
      end

      def destroy
        @page.destroy!
        redirect_to admin_website_pages_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.page"))
      end

      def publish
        @page.create_revision!(author: current_user)
        result = ::Website::PagePublisher.call(page: @page, actor: current_user)
        if result.success?
          redirect_to admin_website_page_path(@page), notice: t("mcweb.admin.website.published", default: "Published")
        else
          redirect_to admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      def schedule
        publish_at = Time.zone.parse(params[:publish_at].to_s)
        result = ::Website::PagePublisher.call(page: @page, publish_at: publish_at, actor: current_user)
        if result.success?
          redirect_to admin_website_page_path(@page), notice: t("mcweb.admin.website.scheduled", default: "Scheduled")
        else
          redirect_to admin_website_page_path(@page), alert: service_error_message(result)
        end
      end

      private

      def set_page
        @page = ::Website::Page.find_by!(public_id: params[:id])
      end

      def page_params
        permitted = params.require(:page).permit(
          :title, :slug, :page_type, :status, :website_theme_id, :scheduled_at,
          seo: {},
          translations: {}
        )
        permitted[:seo] = permitted[:seo].to_unsafe_h if permitted[:seo].is_a?(ActionController::Parameters)
        permitted[:translations] = permitted[:translations].to_unsafe_h if permitted[:translations].is_a?(ActionController::Parameters)
        permitted
      end

      def form_props(page)
        {
          title: page.persisted? ? t("mcweb.admin.website.pages.edit") : t("mcweb.admin.website.pages.new"),
          page: serialize_page_form(page),
          blocks: page.persisted? ? page.blocks.unscope(:order).order(:position).map { |b| serialize_block(b) } : [],
          pageTypeOptions: %w[custom home landing].map { |value| { value:, label: value } },
          statusOptions: ::Website::Page.statuses.keys.map { |value| { value:, label: value } },
          themeOptions: ::Website::Theme.order(:name).map { |t| { value: t.id, label: t.name } },
          locales: %w[en zh-CN],
          submitUrl: page.persisted? ? admin_website_page_path(page) : admin_website_pages_path,
          publishUrl: page.persisted? ? publish_admin_website_page_path(page) : nil,
          scheduleUrl: page.persisted? ? schedule_admin_website_page_path(page) : nil,
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
          translations: page.translations.presence || {}
        }
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
          { label: t("mcweb.admin.ui.edit"), href: edit_admin_website_page_path(@page) },
          { label: t("mcweb.admin.website.preview", default: "Preview"), href: preview_url, external: true },
          { label: t("mcweb.admin.website.revisions.title", default: "Revisions"), href: admin_website_page_revisions_path(@page) }
        ]
        if current_user.permission?("website.pages.publish")
          actions << { label: t("mcweb.admin.website.publish", default: "Publish"), href: publish_admin_website_page_path(@page), method: "post" }
        end
        if current_user.permission?("website.pages.edit")
          actions << { label: t("mcweb.admin.ui.delete", default: "Delete"), href: admin_website_page_path(@page), method: "delete", confirm: t("mcweb.admin.website.confirm_delete", default: "Delete this page?") }
        end
        actions
      end
    end
  end
end
