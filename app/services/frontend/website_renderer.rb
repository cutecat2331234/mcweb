# frozen_string_literal: true

require "thread"
require "digest"

module Frontend
  class WebsiteRenderer
    class UnknownAdapter < StandardError; end

    CE_ADAPTER = "ce_inertia_document"
    Adapter = Struct.new(
      :runtime_kind,
      :preview_kind,
      :manifest_path,
      :fingerprint,
      :render,
      :preview,
      keyword_init: true
    )

    class << self
      def register(
        name,
        callable = nil,
        runtime_kind:,
        preview_kind:,
        manifest_path: nil,
        fingerprint:,
        render: nil,
        preview: nil,
        &block
      )
        render_callable = render || callable || block
        unless render_callable.respond_to?(:call) && preview.respond_to?(:call)
          raise ArgumentError, "renderer adapter must provide callable render and preview handlers"
        end
        unless runtime_kind.to_s.in?(%w[inertia_document astro_document]) &&
            preview_kind.to_s.in?(%w[inertia_canvas document_frame])
          raise ArgumentError, "renderer adapter has an unsupported runtime or preview kind"
        end
        normalized_manifest_path = manifest_path.to_s.presence
        if runtime_kind.to_s == "astro_document" && normalized_manifest_path.blank?
          raise ArgumentError, "Astro renderer adapter must declare its asset manifest path"
        end
        if runtime_kind.to_s != "astro_document" && normalized_manifest_path.present?
          raise ArgumentError, "asset manifest paths apply only to Astro renderer adapters"
        end
        fingerprint_callable = fingerprint.respond_to?(:call) ? fingerprint : -> { fingerprint }

        mutex.synchronize do
          key = name.to_s
          raise ArgumentError, "renderer adapter is already registered: #{key}" if adapters.key?(key)

          adapters[key] = Adapter.new(
            runtime_kind: runtime_kind.to_s,
            preview_kind: preview_kind.to_s,
            manifest_path: normalized_manifest_path,
            fingerprint: fingerprint_callable,
            render: render_callable,
            preview:
          ).freeze
        end
      end

      def call(controller:, component:, props:, status: nil)
        descriptor = Frontend::ApplicationRegistry.instance.fetch_application("website")
        Frontend::ApplicationRegistry.instance.assert_component!(
          application_id: "website",
          component:
        )
        adapter = fetch_adapter(descriptor)

        adapter.render.call(controller:, component:, props:, status:)
      end

      def preview(controller:, component:, props:, status: nil)
        descriptor = Frontend::ApplicationRegistry.instance.fetch_application("website")
        Frontend::ApplicationRegistry.instance.assert_component!(
          application_id: "website_preview",
          component:
        )
        adapter = fetch_adapter(descriptor)

        adapter.preview.call(controller:, component:, props:, status:)
      end

      def cache_key
        descriptor = Frontend::ApplicationRegistry.instance.fetch_application("website")
        adapter = fetch_adapter(descriptor)
        [
          descriptor.runtime_owner,
          descriptor.runtime_kind,
          descriptor.entrypoint,
          descriptor.renderer&.product_owner,
          descriptor.renderer&.adapter,
          descriptor.renderer&.contribution_id,
          descriptor.renderer&.preview_kind,
          descriptor.renderer&.manifest_path,
          descriptor.styles.join(","),
          descriptor.locales.join(","),
          renderer_manifest_fingerprint(descriptor.renderer&.manifest_path),
          adapter_fingerprint(adapter)
        ].join(":")
      end

      def registered?(name, runtime_kind: nil, preview_kind: nil, manifest_path: nil)
        adapter = mutex.synchronize { adapters[name.to_s] }
        return false unless adapter

        (runtime_kind.nil? || adapter.runtime_kind == runtime_kind.to_s) &&
          (preview_kind.nil? || adapter.preview_kind == preview_kind.to_s) &&
          adapter.manifest_path == manifest_path.to_s.presence
      end

      private

      def fetch_adapter(descriptor)
        adapter_name = descriptor.renderer&.adapter || CE_ADAPTER
        adapter = mutex.synchronize { adapters[adapter_name] }
        raise UnknownAdapter, "Website renderer adapter is not registered: #{adapter_name}" unless adapter
        unless adapter.runtime_kind == descriptor.runtime_kind &&
            adapter.preview_kind == descriptor.renderer&.preview_kind &&
            adapter.manifest_path == descriptor.renderer&.manifest_path
          raise UnknownAdapter,
            "Website renderer adapter #{adapter_name.inspect} does not match its runtime contract"
        end

        adapter
      end

      def adapter_fingerprint(adapter)
        value = adapter.fingerprint.call.to_s
        if value.blank? || value.match?(/[\x00-\x1f\x7f]/)
          raise UnknownAdapter, "Website renderer adapter returned an invalid asset fingerprint"
        end

        value
      end

      def renderer_manifest_fingerprint(manifest_path)
        return "rails-vite" if manifest_path.blank?

        manifest = Rails.root.join(manifest_path)
        unless manifest.file?
          raise UnknownAdapter, "Website renderer asset manifest is missing: #{manifest_path}"
        end

        Digest::SHA256.file(manifest).hexdigest
      end

      def adapters
        @adapters ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end

    ce_inertia_render = lambda do |controller:, component:, props:, status:|
      options = { inertia: component, props:, layout: "inertia" }
      options[:status] = status if status
      controller.render(**options)
    end
    register CE_ADAPTER,
      runtime_kind: "inertia_document",
      preview_kind: "inertia_canvas",
      fingerprint: lambda {
        manifest = Rails.root.join("public/vite/.vite/manifest.json")
        next Digest::SHA256.file(manifest).hexdigest if manifest.file?

        Digest::SHA256.hexdigest([File.mtime(__FILE__).to_f, File.size(__FILE__)].join(":"))
      },
      render: ce_inertia_render,
      preview: ce_inertia_render
  end
end
