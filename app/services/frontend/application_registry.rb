# frozen_string_literal: true

require "json"
require "pathname"
require "thread"
require "uri"

module Frontend
  class ApplicationRegistry
    class InvalidManifest < StandardError; end
    class UnknownApplication < StandardError; end
    class ComponentBoundaryViolation < StandardError; end

    SCHEMA_VERSION = 1
    ROUTE_KINDS = %w[
      inertia_page
      application_action
      document
      download
      api
      shared_action
    ].freeze
    HTTP_METHODS = %w[GET HEAD POST PUT PATCH DELETE].freeze
    RUNTIME_KINDS = %w[inertia inertia_document astro_document].freeze
    IDENTIFIER = /\A[a-z][a-z0-9_]*\z/
    OWNER_IDENTIFIER = /\A[a-z][a-z0-9_-]*\z/
    COMPONENT_PREFIX = /\A[A-Z][A-Za-z0-9]*(?:\/[A-Z][A-Za-z0-9]*)*\/\z/
    SHARED_ADAPTER_STYLES = %w[tokens shell_foundation app_shell arco_admin].freeze
    SHARED_ADAPTER_LOCALES = %w[core].freeze

    RouteRule = Struct.new(
      :application_id,
      :product_owner,
      :kind,
      :methods,
      :pattern,
      :priority,
      :allowed_source_applications,
      :allowed_source_capabilities,
      :safe_get_path,
      :source,
      :contribution,
      :contribution_id,
      :matcher,
      :specificity,
      keyword_init: true
    ) do
      def matches?(path, method)
        methods.include?(method) && matcher.match?(path)
      end
    end

    RouteMatch = Struct.new(:application, :rule, keyword_init: true) do
      def application_id
        application&.id
      end

      def kind
        rule.kind
      end

      def allowed_source_applications
        rule.allowed_source_applications
      end

      def allowed_source_capabilities
        rule.allowed_source_capabilities
      end

      def safe_get_path
        rule.safe_get_path
      end

      def product_owner
        rule.product_owner
      end
    end

    Projection = Struct.new(:prefix, :owner_application, :source, keyword_init: true)
    Launcher = Struct.new(
      :path,
      :priority,
      :application_id,
      :product_owner,
      :source,
      keyword_init: true
    )
    DraftContract = Struct.new(
      :capability,
      :key_namespace,
      :version,
      :user_scoped,
      :resource_scoped,
      :offline_recovery,
      :clear_on_submit,
      keyword_init: true
    )
    NavigationItem = Struct.new(
      :href,
      :label_key,
      :badge_prop,
      :visibility_prop,
      :module_key,
      :permission_key,
      :permission_any,
      :capability_key,
      :requires_authentication,
      keyword_init: true
    )
    NavigationGroup = Struct.new(:id, :label_key, :items, keyword_init: true)
    ContributionResource = Struct.new(
      :id,
      :product_owner,
      :runtime_owner,
      :adapter_module,
      :page_roots,
      :styles,
      :locales,
      :error_boundary,
      :draft_contract,
      :navigation,
      :accessories,
      :budget,
      :source,
      keyword_init: true
    )
    RendererContract = Struct.new(
      :adapter,
      :contribution_id,
      :product_owner,
      :runtime_owner,
      :preview_kind,
      :manifest_path,
      keyword_init: true
    )

    ComponentClaim = Struct.new(
      :prefix,
      :exact,
      :product_owner,
      :runtime_application_id,
      :contribution_id,
      :source,
      :contribution,
      keyword_init: true
    ) do
      def owns?(component)
        exact ? component == prefix : component.start_with?(prefix)
      end
    end

    Application = Struct.new(
      :id,
      :product_owner,
      :runtime_owner,
      :runtime_kind,
      :entrypoint,
      :landing_path,
      :component_prefixes,
      :component_names,
      :allow_descendant_contributions,
      :projections,
      :shell_adapter,
      :ui_adapter,
      :styles,
      :locales,
      :error_boundaries,
      :capabilities,
      :budget,
      :launcher,
      :route_rules,
      :renderer_adapters,
      :renderer,
      :adapter_modules,
      :contributions,
      :source,
      keyword_init: true
    ) do
      def inertia?
        runtime_kind == "inertia"
      end

      def document_renderer?
        runtime_kind.end_with?("_document")
      end

      def projects?(component, owner_application_id)
        projections.any? do |projection|
          component.start_with?(projection.prefix) &&
            projection.owner_application == owner_application_id
        end
      end
    end

    class << self
      def instance
        return @instance if @instance

        mutex.synchronize do
          @instance ||= new(root: Rails.root)
        end
      end

      def reload!
        mutex.synchronize do
          @instance = new(root: Rails.root)
        end
      end

      private

      def mutex
        @mutex ||= Mutex.new
      end
    end

    attr_reader :applications, :route_rules, :component_claims

    def initialize(root:)
      @root = Pathname(root)
      @manifest_root = @root.join("config/frontend_applications")
      @applications_by_id = {}
      @route_rules = []
      @component_claims = []
      @launchers = []
      @contribution_ids = {}

      load_base_descriptors!
      load_shared_routes!
      load_contributions!
      @applications = @applications_by_id.values.sort_by(&:id)
      validate_registry!
      freeze_registry!
    end

    def application(id)
      @applications_by_id[id.to_s]
    end

    def fetch_application(id)
      application(id) || raise(UnknownApplication, "unknown frontend application: #{id.inspect}")
    end

    def resolve(path:, method:)
      normalized_path = normalize_request_path(path)
      normalized_method = method.to_s.upcase
      rule = @route_rules.find { |candidate| candidate.matches?(normalized_path, normalized_method) }
      return unless rule

      RouteMatch.new(
        application: rule.application_id && fetch_application(rule.application_id),
        rule: rule
      )
    end

    def component_owner(component)
      name = normalize_component_name(component)
      @component_claims.find { |claim| claim.owns?(name) }
    end

    def assert_component!(application_id:, component:, product_owner: nil)
      target = fetch_application(application_id)
      name = normalize_component_name(component)
      owner = component_owner(name)
      unless owner
        raise ComponentBoundaryViolation,
          "component #{name.inspect} has no registered product/runtime owner"
      end

      if product_owner.present? && owner.product_owner != product_owner.to_s
        raise ComponentBoundaryViolation,
          "route owner #{product_owner.inspect} cannot render #{name.inspect}; " \
          "component product owner=#{owner.product_owner.inspect}"
      end

      return owner if owner.runtime_application_id == target.id
      return owner if target.projects?(name, owner.runtime_application_id)

      raise ComponentBoundaryViolation,
        "application #{target.id.inspect} cannot render #{name.inspect}; " \
        "owner=#{owner.product_owner.inspect} runtime=#{owner.runtime_application_id.inspect}"
    end

    def launcher_application(path = "/app")
      launcher = @launchers.find { |candidate| candidate.path == path }
      launcher && fetch_application(launcher.application_id)
    end

    def source_allowed?(route_match, application_id)
      source = application(application_id)
      return false unless source

      rule = route_match.rule
      rule.allowed_source_applications.include?(source.id) ||
        (rule.allowed_source_capabilities & source.capabilities).any?
    end

    def validate_runtime_files!
      applications.each do |descriptor|
        if descriptor.runtime_kind == "astro_document"
          manifest_path = descriptor.renderer&.manifest_path
          unless manifest_path.present? && @root.join(manifest_path).file?
            raise InvalidManifest,
              "#{descriptor.source}: Astro renderer manifest #{manifest_path.inspect} does not exist"
          end
          next
        end

        entrypoint = @root.join("app/javascript/entrypoints/#{descriptor.entrypoint}.ts")
        unless entrypoint.file?
          raise InvalidManifest,
            "#{descriptor.source}: entrypoint #{descriptor.entrypoint.inspect} does not exist at #{entrypoint}"
        end

        next unless descriptor.runtime_kind.in?(%w[inertia inertia_document])

        entry_source = entrypoint.read
        style_root = descriptor.id.tr("_", "-")
        unless entry_source.include?("@/styles/applications/#{style_root}.css")
          raise InvalidManifest,
            "#{descriptor.source}: entrypoint #{descriptor.entrypoint.inspect} does not import " \
            "its application style root #{style_root.inspect}"
        end
        unless entry_source.include?("applicationId: '#{descriptor.id}'") ||
            entry_source.include?(%(applicationId: "#{descriptor.id}"))
          raise InvalidManifest,
            "#{descriptor.source}: entrypoint #{descriptor.entrypoint.inspect} does not bind " \
            "application #{descriptor.id.inspect}"
        end
        if entry_source.include?("../pages/**/*.vue") || entry_source.match?(/!\.\.\/pages\//)
          raise InvalidManifest,
            "#{descriptor.source}: entrypoint #{descriptor.entrypoint.inspect} uses an umbrella page resolver"
        end
      end

      applications.each do |descriptor|
        descriptor.adapter_modules.each do |adapter_module|
          next if @root.join(adapter_module).file?

          raise InvalidManifest,
            "#{descriptor.source}: adapter module #{adapter_module.inspect} does not exist"
        end

        descriptor.contributions.each do |contribution|
          contribution.page_roots.each do |page_root|
            next if @root.join(page_root).directory?

            raise InvalidManifest,
              "#{contribution.source}: page root #{page_root.inspect} does not exist"
          end
        end

        descriptor.renderer_adapters.each do |renderer_adapter|
          next if Frontend::WebsiteRenderer.registered?(
            renderer_adapter,
            runtime_kind: descriptor.runtime_kind,
            preview_kind: descriptor.renderer&.preview_kind,
            manifest_path: descriptor.renderer&.manifest_path
          )

          raise InvalidManifest,
            "#{descriptor.source}: Website renderer adapter #{renderer_adapter.inspect} is not registered"
        end
      end

      true
    end

    private

    def load_base_descriptors!
      paths = @manifest_root.join("base/*.json").then { |pattern| Dir.glob(pattern.to_s).sort }
      raise InvalidManifest, "no base frontend application descriptors found" if paths.empty?

      paths.each do |path|
        source = relative_source(path)
        descriptor = build_application(read_json(path), source:, contribution: false)
        if @applications_by_id.key?(descriptor.id)
          raise InvalidManifest, "#{source}: duplicate application id #{descriptor.id.inspect}"
        end

        @applications_by_id[descriptor.id] = descriptor
        register_application_claims!(descriptor, contribution: false)
        register_launcher!(descriptor)
        @route_rules.concat(descriptor.route_rules)
      end
    end

    def load_shared_routes!
      path = @manifest_root.join("shared_routes.json")
      data = read_json(path)
      validate_schema_version!(data, relative_source(path))
      assert_exact_keys!(data, %w[schema_version routes], relative_source(path))

      Array(data["routes"]).each_with_index do |raw_rule, index|
        @route_rules << build_route_rule(
          raw_rule,
          application_id: nil,
          product_owner: "ce",
          source: "#{relative_source(path)}#routes[#{index}]",
          contribution: false
        )
      end
    end

    def load_contributions!
      paths = @manifest_root.join("contributions/*.json").then { |pattern| Dir.glob(pattern.to_s).sort }
      contributions = paths.map { |path| [ read_json(path), relative_source(path) ] }

      contributions.each do |data, source|
        validate_contribution_header!(data, source)
        next unless data.key?("creates_application")

        assert_exact_keys!(
          data,
          %w[
            schema_version contribution_id product_owner runtime_owner
            creates_application adapter_module page_roots draft_contract accessories
          ],
          source
        )

        raw_application = data.fetch("creates_application").merge(
          "product_owner" => data.fetch("product_owner"),
          "runtime_owner" => data.fetch("runtime_owner")
        )
        descriptor = build_application(
          raw_application,
          source:,
          contribution: true,
          contribution_id: data.fetch("contribution_id")
        )
        if @applications_by_id.key?(descriptor.id)
          raise InvalidManifest, "#{source}: contribution creates duplicate application #{descriptor.id.inspect}"
        end

        adapter_module = data["adapter_module"]
        accessories = validate_string_list!(
          data.fetch("accessories", []),
          source,
          field: "accessories"
        ).map { |name| validate_adapter_name!(name, source) }
        if accessories.any? && !descriptor.runtime_kind.in?(%w[inertia inertia_document])
          raise InvalidManifest, "#{source}: runtime accessories require an Inertia application"
        end
        if (descriptor.runtime_kind == "inertia" || accessories.any?) && adapter_module.blank?
          raise InvalidManifest,
            "#{source}: created Inertia applications and runtime accessories require adapter_module"
        end
        if adapter_module.present?
          descriptor.adapter_modules << validate_adapter_module!(adapter_module, source, descriptor.id)
        end
        descriptor.contributions << ContributionResource.new(
          id: data.fetch("contribution_id"),
          product_owner: descriptor.product_owner,
          runtime_owner: descriptor.runtime_owner,
          adapter_module: descriptor.adapter_modules.last,
          page_roots: validate_page_roots!(
            data.fetch("page_roots", [ "app/javascript/pages" ]),
            source
          ),
          styles: descriptor.styles.reject { |style| SHARED_ADAPTER_STYLES.include?(style) },
          locales: descriptor.locales.reject { |locale| SHARED_ADAPTER_LOCALES.include?(locale) },
          error_boundary: descriptor.error_boundaries.first,
          draft_contract: data["draft_contract"].present? ?
            build_draft_contract(data["draft_contract"], source) : nil,
          navigation: [],
          accessories:,
          budget: descriptor.budget,
          source:
        )

        @applications_by_id[descriptor.id] = descriptor
        register_application_claims!(
          descriptor,
          contribution: true,
          contribution_id: data.fetch("contribution_id")
        )
        register_launcher!(descriptor)
        @route_rules.concat(descriptor.route_rules)
      end

      contributions.each do |data, source|
        next unless data.key?("extends_application")

        apply_extension!(data, source)
      end
    end

    def build_application(data, source:, contribution:, contribution_id: nil)
      required = %w[
        schema_version id product_owner runtime_owner runtime_kind entrypoint landing_path
        component_prefixes component_names projections shell_adapter ui_adapter styles locales
        error_boundary budget routes
      ]
      optional = %w[
        allow_descendant_contributions capabilities renderer_adapter renderer_preview_kind
        renderer_manifest_path launcher
      ]
      validate_schema_version!(data, source)
      assert_required_keys!(data, required, source)
      assert_exact_keys!(data, required + optional, source)

      id = validate_identifier!(data.fetch("id"), source, field: "id")
      product_owner = validate_owner!(data.fetch("product_owner"), source, field: "product_owner")
      runtime_owner = validate_owner!(data.fetch("runtime_owner"), source, field: "runtime_owner")
      runtime_kind = data.fetch("runtime_kind").to_s
      unless RUNTIME_KINDS.include?(runtime_kind)
        raise InvalidManifest, "#{source}: unsupported runtime_kind #{runtime_kind.inspect}"
      end

      entrypoint = validate_entrypoint!(data.fetch("entrypoint"), source)
      landing_path = validate_literal_path!(data.fetch("landing_path"), source, field: "landing_path")
      component_prefixes = validate_component_prefixes!(
        data.fetch("component_prefixes"),
        source,
        allow_empty: id == "website_preview"
      )
      component_names = validate_component_names!(data.fetch("component_names"), source)
      projections = build_projections(data.fetch("projections"), source)
      styles = validate_string_list!(data.fetch("styles"), source, field: "styles", allow_empty: false)
      locales = validate_string_list!(data.fetch("locales"), source, field: "locales", allow_empty: false)
      capabilities = validate_string_list!(data.fetch("capabilities", []), source, field: "capabilities")
      budget = validate_budget!(data.fetch("budget"), source)

      route_rules = Array(data.fetch("routes")).each_with_index.map do |raw_rule, index|
        build_route_rule(
          raw_rule,
          application_id: id,
          product_owner:,
          source: "#{source}#routes[#{index}]",
          contribution:,
          contribution_id:
        )
      end
      raise InvalidManifest, "#{source}: routes must not be empty" if route_rules.empty?

      renderer_adapters = []
      if data["renderer_adapter"].present?
        renderer_adapters << validate_adapter_name!(data["renderer_adapter"], source)
      end
      if runtime_kind == "inertia" && renderer_adapters.any?
        raise InvalidManifest, "#{source}: Inertia applications cannot declare a document renderer"
      end
      if runtime_kind != "inertia" && renderer_adapters.length != 1
        raise InvalidManifest, "#{source}: document applications require exactly one renderer_adapter"
      end
      preview_kind = data["renderer_preview_kind"].presence
      if renderer_adapters.any? && !%w[inertia_canvas document_frame].include?(preview_kind)
        raise InvalidManifest, "#{source}: document renderer requires a supported renderer_preview_kind"
      end
      manifest_path = data["renderer_manifest_path"].presence &&
        validate_repository_path!(data["renderer_manifest_path"], source, "renderer_manifest_path")
      if runtime_kind == "astro_document" && manifest_path.blank?
        raise InvalidManifest, "#{source}: Astro document renderer requires renderer_manifest_path"
      end
      if runtime_kind != "astro_document" && manifest_path.present?
        raise InvalidManifest, "#{source}: renderer_manifest_path applies only to Astro renderers"
      end
      launcher = data["launcher"].present? ? build_launcher(data["launcher"], id, product_owner, source) : nil

      Application.new(
        id:,
        product_owner:,
        runtime_owner:,
        runtime_kind:,
        entrypoint:,
        landing_path:,
        component_prefixes:,
        component_names:,
        allow_descendant_contributions: data.fetch("allow_descendant_contributions", false) == true,
        projections:,
        shell_adapter: validate_adapter_name!(data.fetch("shell_adapter"), source),
        ui_adapter: validate_adapter_name!(data.fetch("ui_adapter"), source),
        styles:,
        locales:,
        error_boundaries: [ validate_adapter_name!(data.fetch("error_boundary"), source) ],
        capabilities:,
        budget:,
        launcher:,
        route_rules:,
        renderer_adapters:,
        renderer: renderer_adapters.any? ? RendererContract.new(
          adapter: renderer_adapters.first,
          contribution_id:,
          product_owner:,
          runtime_owner:,
          preview_kind:,
          manifest_path:
        ) : nil,
        adapter_modules: [],
        contributions: [],
        source:
      )
    end

    def validate_contribution_header!(data, source)
      validate_schema_version!(data, source)
      required = %w[schema_version contribution_id product_owner runtime_owner]
      assert_required_keys!(data, required, source)
      contribution_id = data.fetch("contribution_id").to_s
      unless contribution_id.match?(/\A[a-z][a-z0-9_.-]*\z/)
        raise InvalidManifest, "#{source}: invalid contribution_id #{contribution_id.inspect}"
      end
      if @contribution_ids.key?(contribution_id)
        raise InvalidManifest,
          "#{source}: duplicate contribution_id #{contribution_id.inspect}; " \
          "first declared by #{@contribution_ids.fetch(contribution_id)}"
      end

      validate_owner!(data.fetch("product_owner"), source, field: "product_owner")
      validate_owner!(data.fetch("runtime_owner"), source, field: "runtime_owner")
      modes = %w[creates_application extends_application].count { |key| data.key?(key) }
      unless modes == 1
        raise InvalidManifest,
          "#{source}: contribution must declare exactly one of creates_application or extends_application"
      end

      @contribution_ids[contribution_id] = source
    end

    def apply_extension!(data, source)
      allowed = %w[
        schema_version contribution_id product_owner runtime_owner extends_application
        component_prefixes component_names routes styles locales capabilities error_boundary
        adapter_module page_roots draft_contract navigation accessories budget renderer_adapter exclusive_renderer
        renderer_runtime_kind renderer_entrypoint renderer_shell_adapter renderer_ui_adapter
        renderer_preview_kind renderer_manifest_path
      ]
      assert_exact_keys!(data, allowed, source)
      target = fetch_application(data.fetch("extends_application"))
      product_owner = validate_owner!(data.fetch("product_owner"), source, field: "product_owner")
      runtime_owner = validate_owner!(data.fetch("runtime_owner"), source, field: "runtime_owner")
      renderer_replacement = data["renderer_adapter"].present? &&
        data.fetch("exclusive_renderer", false) == true && target.id == "website"
      unless runtime_owner == target.runtime_owner || renderer_replacement
        raise InvalidManifest,
          "#{source}: extension runtime_owner #{runtime_owner.inspect} must match " \
          "#{target.id} runtime owner #{target.runtime_owner.inspect}"
      end

      prefixes = validate_component_prefixes!(data.fetch("component_prefixes", []), source, allow_empty: true)
      prefixes.each do |prefix|
        target.component_prefixes << prefix
        @component_claims << ComponentClaim.new(
          prefix:,
          exact: false,
          product_owner:,
          runtime_application_id: target.id,
          contribution_id: data.fetch("contribution_id"),
          source:,
          contribution: true
        )
      end

      names = validate_component_names!(data.fetch("component_names", []), source)
      names.each do |name|
        target.component_names << name
        @component_claims << ComponentClaim.new(
          prefix: name,
          exact: true,
          product_owner:,
          runtime_application_id: target.id,
          contribution_id: data.fetch("contribution_id"),
          source:,
          contribution: true
        )
      end

      contribution_styles = validate_string_list!(data.fetch("styles", []), source, field: "styles")
      contribution_locales = validate_string_list!(data.fetch("locales", []), source, field: "locales")
      target.styles.concat(contribution_styles)
      target.locales.concat(contribution_locales)
      target.capabilities.concat(validate_string_list!(data.fetch("capabilities", []), source, field: "capabilities"))
      contribution_error_boundary = data["error_boundary"].present? ?
        validate_adapter_name!(data["error_boundary"], source) : nil
      target.error_boundaries << contribution_error_boundary if contribution_error_boundary
      contribution_navigation = build_navigation(data.fetch("navigation", []), source)
      contribution_accessories = validate_string_list!(
        data.fetch("accessories", []),
        source,
        field: "accessories"
      ).map { |name| validate_adapter_name!(name, source) }
      if contribution_accessories.any? && !target.runtime_kind.in?(%w[inertia inertia_document])
        raise InvalidManifest, "#{source}: runtime accessories require an Inertia application"
      end

      adapter_required = !renderer_replacement && (prefixes.any? || names.any? ||
        data.fetch("styles", []).any? || data.fetch("locales", []).any? ||
        data["error_boundary"].present? || data["draft_contract"].present? ||
        contribution_navigation.any? || contribution_accessories.any?)
      if adapter_required && data["budget"].blank?
        raise InvalidManifest, "#{source}: frontend resource/page extensions require budget"
      end
      if adapter_required && data["adapter_module"].blank?
        raise InvalidManifest, "#{source}: frontend resource/page extensions require adapter_module"
      end
      if data["adapter_module"].present?
        target.adapter_modules << validate_adapter_module!(data["adapter_module"], source, target.id)
      end
      contribution_adapter_module = data["adapter_module"].present? ?
        validate_adapter_module!(data["adapter_module"], source, target.id) : nil
      contribution_page_roots = validate_page_roots!(
        data.fetch("page_roots", [ "app/javascript/pages" ]),
        source
      )
      contribution_budget = data["budget"].present? ? validate_budget!(data["budget"], source) : nil
      target.contributions << ContributionResource.new(
        id: data.fetch("contribution_id"),
        product_owner:,
        runtime_owner:,
        adapter_module: contribution_adapter_module,
        page_roots: contribution_page_roots,
        styles: contribution_styles,
        locales: contribution_locales,
        error_boundary: contribution_error_boundary,
        draft_contract: data["draft_contract"].present? ?
          build_draft_contract(data["draft_contract"], source) : nil,
        navigation: contribution_navigation,
        accessories: contribution_accessories,
        budget: contribution_budget,
        source:
      )
      merge_application_budget!(target.budget, contribution_budget) if contribution_budget && !renderer_replacement

      Array(data.fetch("routes", [])).each_with_index do |raw_rule, index|
        rule = build_route_rule(
          raw_rule,
          application_id: target.id,
          product_owner:,
          source: "#{source}#routes[#{index}]",
          contribution: true,
          contribution_id: data.fetch("contribution_id")
        )
        target.route_rules << rule
        @route_rules << rule
      end

      return unless data["renderer_adapter"].present?

      adapter = validate_adapter_name!(data["renderer_adapter"], source)
      exclusive = data.fetch("exclusive_renderer", false) == true
      unless target.id == "website" && exclusive
        raise InvalidManifest,
          "#{source}: renderer_adapter extensions are allowed only as an exclusive Website renderer"
      end
      if target.renderer_adapters.any? && target.renderer_adapters != [ Frontend::WebsiteRenderer::CE_ADAPTER ]
        raise InvalidManifest,
          "#{source}: Website already has an exclusive renderer adapter #{target.renderer_adapters.first.inspect}"
      end
      previous_renderer_contributions = target.contributions.reject do |contribution|
        contribution.id == data.fetch("contribution_id")
      end
      if data["adapter_module"].present? || data["draft_contract"].present? ||
          prefixes.any? || names.any? || contribution_navigation.any? ||
          contribution_accessories.any? ||
          Array(data.fetch("capabilities", [])).any? ||
          target.adapter_modules.any? || previous_renderer_contributions.any?
        raise InvalidManifest,
          "#{source}: exclusive Website renderer cannot share Inertia adapters, pages, navigation, " \
          "accessories, or draft resources"
      end
      invalid_renderer_route = target.route_rules.find do |rule|
        rule.contribution_id == data.fetch("contribution_id") &&
          !%w[document download api].include?(rule.kind)
      end
      if invalid_renderer_route
        raise InvalidManifest,
          "#{source}: exclusive Website renderer routes must be document, download, or api"
      end

      renderer_required = %w[
        renderer_runtime_kind renderer_entrypoint renderer_shell_adapter renderer_ui_adapter
        renderer_preview_kind styles locales error_boundary budget
      ]
      assert_required_keys!(data, renderer_required, source)
      renderer_runtime_kind = data.fetch("renderer_runtime_kind").to_s
      unless %w[inertia_document astro_document].include?(renderer_runtime_kind)
        raise InvalidManifest,
          "#{source}: exclusive Website renderer must be inertia_document or astro_document"
      end
      if contribution_styles.empty? || contribution_locales.empty? || contribution_error_boundary.nil?
        raise InvalidManifest,
          "#{source}: exclusive Website renderer requires styles, locales, and error_boundary"
      end

      target.runtime_owner = runtime_owner
      target.runtime_kind = renderer_runtime_kind
      target.entrypoint = validate_entrypoint!(data.fetch("renderer_entrypoint"), source)
      target.shell_adapter = validate_adapter_name!(data.fetch("renderer_shell_adapter"), source)
      target.ui_adapter = validate_adapter_name!(data.fetch("renderer_ui_adapter"), source)
      if renderer_runtime_kind == "astro_document" && target.ui_adapter != "astro_custom"
        raise InvalidManifest, "#{source}: Astro Website renderer must use astro_custom UI"
      end
      preview_kind = data.fetch("renderer_preview_kind").to_s
      unless %w[inertia_canvas document_frame].include?(preview_kind)
        raise InvalidManifest, "#{source}: unsupported renderer_preview_kind #{preview_kind.inspect}"
      end
      manifest_path = if renderer_runtime_kind == "astro_document"
        validate_repository_path!(
          data.fetch("renderer_manifest_path"),
          source,
          "renderer_manifest_path"
        )
      elsif data["renderer_manifest_path"].present?
        raise InvalidManifest, "#{source}: renderer_manifest_path applies only to Astro renderers"
      end
      target.styles.replace(contribution_styles)
      target.locales.replace(contribution_locales)
      target.error_boundaries.replace([ contribution_error_boundary ])
      target.budget.replace(validate_budget!(data.fetch("budget"), source))

      target.renderer_adapters.replace([ adapter ])
      target.renderer = RendererContract.new(
        adapter:,
        contribution_id: data.fetch("contribution_id"),
        product_owner:,
        runtime_owner:,
        preview_kind:,
        manifest_path:
      )
    end

    def register_application_claims!(descriptor, contribution:, contribution_id: nil)
      descriptor.component_prefixes.each do |prefix|
        @component_claims << ComponentClaim.new(
          prefix:,
          exact: false,
          product_owner: descriptor.product_owner,
          runtime_application_id: descriptor.id,
          contribution_id:,
          source: descriptor.source,
          contribution:
        )
      end
      descriptor.component_names.each do |name|
        @component_claims << ComponentClaim.new(
          prefix: name,
          exact: true,
          product_owner: descriptor.product_owner,
          runtime_application_id: descriptor.id,
          contribution_id:,
          source: descriptor.source,
          contribution:
        )
      end
    end

    def register_launcher!(descriptor)
      @launchers << descriptor.launcher if descriptor.launcher
    end

    def build_launcher(raw_launcher, application_id, product_owner, source)
      launcher_source = "#{source}#launcher"
      assert_exact_keys!(raw_launcher, %w[path priority], launcher_source)
      path = validate_literal_path!(raw_launcher.fetch("path"), launcher_source, field: "path")
      priority = Integer(raw_launcher.fetch("priority"), exception: false)
      unless priority && priority >= 0
        raise InvalidManifest, "#{launcher_source}: priority must be a non-negative integer"
      end

      Launcher.new(
        path:,
        priority:,
        application_id:,
        product_owner:,
        source: launcher_source
      )
    end

    def build_projections(raw_projections, source)
      Array(raw_projections).each_with_index.map do |raw, index|
        item_source = "#{source}#projections[#{index}]"
        assert_exact_keys!(raw, %w[prefix owner_application], item_source)
        Projection.new(
          prefix: validate_component_prefix!(raw.fetch("prefix"), item_source),
          owner_application: validate_identifier!(
            raw.fetch("owner_application"),
            item_source,
            field: "owner_application"
          ),
          source: item_source
        )
      end
    end

    def build_navigation(raw_navigation, source)
      groups = Array(raw_navigation).each_with_index.map do |raw_group, group_index|
        group_source = "#{source}#navigation[#{group_index}]"
        assert_required_keys!(raw_group, %w[id label_key items], group_source)
        assert_exact_keys!(raw_group, %w[id label_key items], group_source)
        items = Array(raw_group.fetch("items")).each_with_index.map do |raw_item, item_index|
          item_source = "#{group_source}#items[#{item_index}]"
          assert_required_keys!(raw_item, %w[href label_key], item_source)
          assert_exact_keys!(
            raw_item,
            %w[
              href label_key badge_prop visibility_prop module_key permission_key
              permission_any capability_key requires_authentication
            ],
            item_source
          )
          authentication = raw_item.fetch("requires_authentication", false)
          unless authentication.in?([ true, false ])
            raise InvalidManifest,
              "#{item_source}: requires_authentication must be a boolean"
          end
          permission_any = if raw_item.key?("permission_any")
            validate_string_list!(
              raw_item["permission_any"],
              item_source,
              field: "permission_any",
              allow_empty: false
            ).map { |permission| validate_adapter_name!(permission, item_source) }
          else
            []
          end
          NavigationItem.new(
            href: validate_literal_path!(raw_item.fetch("href"), item_source, field: "href"),
            label_key: validate_locale_key!(raw_item.fetch("label_key"), item_source),
            badge_prop: raw_item["badge_prop"].presence &&
              validate_adapter_name!(raw_item["badge_prop"], item_source),
            visibility_prop: raw_item["visibility_prop"].presence &&
              validate_adapter_name!(raw_item["visibility_prop"], item_source),
            module_key: raw_item["module_key"].presence &&
              validate_adapter_name!(raw_item["module_key"], item_source),
            permission_key: raw_item["permission_key"].presence &&
              validate_adapter_name!(raw_item["permission_key"], item_source),
            permission_any:,
            capability_key: raw_item["capability_key"].presence &&
              validate_adapter_name!(raw_item["capability_key"], item_source),
            requires_authentication: authentication
          )
        end
        if items.empty?
          raise InvalidManifest, "#{group_source}: navigation group items must not be empty"
        end
        NavigationGroup.new(
          id: validate_adapter_name!(raw_group.fetch("id"), group_source),
          label_key: validate_locale_key!(raw_group.fetch("label_key"), group_source),
          items:
        )
      end
      ensure_unique!(groups.map(&:id), source, "navigation group ids")
      groups
    end

    def build_route_rule(
      raw,
      application_id:,
      product_owner:,
      source:,
      contribution:,
      contribution_id: nil
    )
      allowed = %w[
        kind methods pattern priority allowed_source_applications
        allowed_source_capabilities safe_get_path
      ]
      required = %w[kind methods pattern priority]
      assert_required_keys!(raw, required, source)
      assert_exact_keys!(raw, allowed, source)

      kind = raw.fetch("kind").to_s
      raise InvalidManifest, "#{source}: unsupported route kind #{kind.inspect}" unless ROUTE_KINDS.include?(kind)

      methods = validate_methods!(raw.fetch("methods"), source)
      validate_route_kind_methods!(kind, methods, source)
      pattern = validate_route_pattern!(raw.fetch("pattern"), source)
      priority = Integer(raw.fetch("priority"), exception: false)
      unless priority && priority >= 0
        raise InvalidManifest, "#{source}: priority must be a non-negative integer"
      end

      allowed_sources = validate_string_list!(
        raw.fetch("allowed_source_applications", []),
        source,
        field: "allowed_source_applications"
      )
      allowed_capabilities = validate_string_list!(
        raw.fetch("allowed_source_capabilities", []),
        source,
        field: "allowed_source_capabilities"
      )
      safe_get_path = if raw["safe_get_path"].present?
        validate_literal_path!(raw["safe_get_path"], source, field: "safe_get_path")
      end

      if kind == "shared_action"
        if (allowed_sources.empty? && allowed_capabilities.empty?) || safe_get_path.blank?
          raise InvalidManifest,
            "#{source}: shared_action requires allowed source ids/capabilities and safe_get_path"
        end
      elsif allowed_sources.any? || allowed_capabilities.any? || safe_get_path.present?
        raise InvalidManifest,
          "#{source}: allowed sources/safe_get_path are valid only for shared_action"
      end

      RouteRule.new(
        application_id:,
        product_owner:,
        kind:,
        methods: methods.freeze,
        pattern:,
        priority:,
        allowed_source_applications: allowed_sources.freeze,
        allowed_source_capabilities: allowed_capabilities.freeze,
        safe_get_path:,
        source:,
        contribution:,
        contribution_id:,
        matcher: compile_route_pattern(pattern),
        specificity: pattern.delete("*").length
      )
    end

    def validate_registry!
      validate_projection_owners!
      validate_component_claims!
      validate_route_rules!
      validate_shared_action_sources!
      validate_safe_get_paths!
      validate_launchers!
      validate_application_resources!
      validate_budget_components!
    end

    def validate_projection_owners!
      applications.each do |descriptor|
        descriptor.projections.each do |projection|
          owner = application(projection.owner_application)
          unless owner
            raise InvalidManifest,
              "#{projection.source}: projection owner #{projection.owner_application.inspect} does not exist"
          end
          unless owner.component_prefixes.any? { |prefix| projection.prefix.start_with?(prefix) || prefix.start_with?(projection.prefix) }
            raise InvalidManifest,
              "#{projection.source}: projection #{projection.prefix.inspect} is not owned by #{owner.id.inspect}"
          end
        end
      end
    end

    def validate_component_claims!
      @component_claims.combination(2) do |left, right|
        next unless component_claim_overlap?(left, right)

        if left.prefix == right.prefix && left.exact == right.exact
          raise InvalidManifest,
            "duplicate component claim #{left.prefix.inspect}: #{left.source} and #{right.source}"
        end

        if left.contribution && right.contribution
          raise InvalidManifest,
            "sibling contribution component claims may not overlap: " \
            "#{left.source} and #{right.source}"
        end

        parent, child = component_claim_parent_child(left, right)
        parent_application = fetch_application(parent.runtime_application_id)
        allowed = parent_application.allow_descendant_contributions && child.contribution
        next if allowed

        raise InvalidManifest,
          "component claim overlap #{parent.prefix.inspect} (#{parent.source}) and " \
          "#{child.prefix.inspect} (#{child.source}) is not an allowed descendant contribution"
      end

      @component_claims.sort_by! { |claim| [ -claim.prefix.length, claim.prefix ] }
    end

    def validate_route_rules!
      claims = {}
      @route_rules.each do |rule|
        rule.methods.each do |method|
          key = [ method, rule.pattern ]
          previous = claims[key]
          if previous
            raise InvalidManifest,
              "duplicate route claim #{method} #{rule.pattern}: #{previous.source} and #{rule.source}"
          end
          claims[key] = rule
        end
      end


      @route_rules.combination(2) do |left, right|
        next if (left.methods & right.methods).empty?
        next unless route_patterns_overlap?(left, right)

        validate_route_overlap!(left, right)
      end

      @route_rules.sort_by! do |rule|
        [ -rule.priority, -rule.specificity, rule.pattern, rule.application_id.to_s, rule.source ]
      end
    end

    def validate_budget_components!
      applications.each do |descriptor|
        descriptor.budget.fetch("representative_paths").each do |path|
          route = resolve(path:, method: "GET")
          unless route&.application_id == descriptor.id && route.kind.in?(%w[inertia_page document])
            raise InvalidManifest,
              "#{descriptor.source}#budget: #{path.inspect} is not an owned GET page/document"
          end
        end
        descriptor.budget.fetch("representative_components", []).each do |component|
          assert_component!(application_id: descriptor.id, component:)
        rescue ComponentBoundaryViolation => error
          raise InvalidManifest, "#{descriptor.source}#budget: #{error.message}"
        end

        descriptor.contributions.each do |contribution|
          next unless contribution.budget

          renderer_budget = descriptor.renderer&.contribution_id == contribution.id
          application_surface_budget = contribution.accessories.any?
          contribution.budget.fetch("representative_paths").each do |path|
            route = resolve(path:, method: "GET")
            valid = route&.application_id == descriptor.id &&
              route.kind.in?(%w[inertia_page document]) &&
              (renderer_budget || application_surface_budget ||
                route.rule.contribution_id == contribution.id)
            next if valid

            raise InvalidManifest,
              "#{contribution.source}#budget: #{path.inspect} is not owned by #{contribution.id}"
          end
          contribution.budget.fetch("representative_components", []).each do |component|
            owner = assert_component!(application_id: descriptor.id, component:)
            if contribution.adapter_module && owner.contribution_id != contribution.id
              raise InvalidManifest,
                "#{contribution.source}#budget: #{component.inspect} belongs to " \
                "#{owner.contribution_id || 'base'}"
            end
          rescue ComponentBoundaryViolation => error
            raise InvalidManifest, "#{contribution.source}#budget: #{error.message}"
          end
        end
      end
    end

    def validate_route_overlap!(left, right)
      same_application = left.application_id == right.application_id
      same_product_owner = left.product_owner == right.product_owner
      same_contribution = left.contribution == right.contribution &&
        left.contribution_id == right.contribution_id
      if same_application && same_product_owner && same_contribution
        return if left.kind == right.kind
        left_child = strict_descendant_route?(left.pattern, right.pattern) &&
          left.priority > right.priority
        right_child = strict_descendant_route?(right.pattern, left.pattern) &&
          right.priority > left.priority
        return if left_child || right_child

        raise InvalidManifest,
          "overlapping route kinds require a higher-priority strict descendant: " \
          "#{left.source} and #{right.source}"
      end

      if left.application_id.nil? || right.application_id.nil?
        shared, owned = left.application_id.nil? ? [ left, right ] : [ right, left ]
        return if shared.priority > owned.priority

        raise InvalidManifest,
          "shared route #{shared.source} must outrank overlapping owned route #{owned.source}"
      end

      if website_fallback_route?(left) || website_fallback_route?(right)
        fallback, owned = website_fallback_route?(left) ? [ left, right ] : [ right, left ]
        return if owned.priority > fallback.priority

        raise InvalidManifest,
          "Website fallback #{fallback.source} must have lower priority than #{owned.source}"
      end

      if preview_admin_overlap?(left, right)
        preview, admin = left.application_id == "website_preview" ? [ left, right ] : [ right, left ]
        return if preview.priority > admin.priority

        raise InvalidManifest,
          "Website Preview route #{preview.source} must outrank Admin route #{admin.source}"
      end

      if same_application
        if left.contribution && right.contribution
          raise InvalidManifest,
            "distinct contributions may not overlap routes: #{left.source} and #{right.source}"
        end

        child, parent = left.contribution && !right.contribution ? [ left, right ] : [ right, left ]
        allowed = child.contribution && strict_descendant_route?(child.pattern, parent.pattern) &&
          child.priority > parent.priority
        return if allowed

        raise InvalidManifest,
          "contribution route #{child.source} may only claim a higher-priority strict descendant " \
          "of inherited route #{parent.source}"
      end

      raise InvalidManifest,
        "overlapping frontend routes have different runtimes: #{left.source} and #{right.source}"
    end

    def route_patterns_overlap?(left, right)
      return false if exact_parent_and_descendant_glob?(left.pattern, right.pattern)

      route_segment_patterns_overlap?(
        left.pattern.split("/", -1),
        right.pattern.split("/", -1),
        0,
        0,
        {}
      )
    end

    def exact_parent_and_descendant_glob?(left, right)
      [ [ left, right ], [ right, left ] ].any? do |parent, descendant|
        !parent.include?("*") && descendant == "#{parent}/**"
      end
    end

    def route_segment_patterns_overlap?(left, right, left_index, right_index, memo)
      key = [ left_index, right_index ]
      return memo[key] if memo.key?(key)
      return memo[key] = true if left_index == left.length && right_index == right.length
      if left_index == left.length
        return memo[key] = right[right_index..].all? { |segment| segment == "**" }
      end
      if right_index == right.length
        return memo[key] = left[left_index..].all? { |segment| segment == "**" }
      end

      left_segment = left[left_index]
      right_segment = right[right_index]
      memo[key] = if left_segment == "**" && right_segment == "**"
        route_segment_patterns_overlap?(left, right, left_index + 1, right_index, memo) ||
          route_segment_patterns_overlap?(left, right, left_index, right_index + 1, memo)
      elsif left_segment == "**"
        route_segment_patterns_overlap?(left, right, left_index + 1, right_index, memo) ||
          route_segment_patterns_overlap?(left, right, left_index, right_index + 1, memo)
      elsif right_segment == "**"
        route_segment_patterns_overlap?(left, right, left_index, right_index + 1, memo) ||
          route_segment_patterns_overlap?(left, right, left_index + 1, right_index, memo)
      else
        route_segment_patterns_intersect?(left_segment, right_segment) &&
          route_segment_patterns_overlap?(left, right, left_index + 1, right_index + 1, memo)
      end
    end

    def route_segment_patterns_intersect?(left, right)
      return true if left == "*" || right == "*"
      return left == right unless left.include?("*") || right.include?("*")
      return route_segment_regexp(left).match?(right) unless right.include?("*")
      return route_segment_regexp(right).match?(left) unless left.include?("*")

      left_suffix = left.split("*", 2).last
      right_suffix = right.split("*", 2).last
      left_suffix.end_with?(right_suffix) || right_suffix.end_with?(left_suffix)
    end

    def route_segment_regexp(pattern)
      Regexp.new("\\A#{Regexp.escape(pattern).gsub('\\*', '.*')}\\z")
    end

    def route_literal_prefix(pattern)
      wildcard = pattern.index("*")
      wildcard ? pattern[0...wildcard] : pattern
    end

    def strict_descendant_route?(child_pattern, parent_pattern)
      if parent_pattern.end_with?("/**")
        parent_root = parent_pattern.delete_suffix("**")
        return child_pattern != parent_pattern && child_pattern.start_with?(parent_root)
      end

      child_prefix = route_literal_prefix(child_pattern)
      parent_prefix = route_literal_prefix(parent_pattern)
      parent_pattern.include?("*") && child_prefix.start_with?(parent_prefix) &&
        child_prefix.length > parent_prefix.length && child_pattern != parent_pattern
    end

    def website_fallback_route?(rule)
      rule.application_id == "website" && rule.pattern == "/*"
    end

    def preview_admin_overlap?(left, right)
      [ left.application_id, right.application_id ].sort == %w[admin website_preview]
    end

    def validate_shared_action_sources!
      known_ids = @applications_by_id.keys
      known_capabilities = applications.flat_map(&:capabilities).uniq
      @route_rules.select { |rule| rule.kind == "shared_action" }.each do |rule|
        unknown = rule.allowed_source_applications - known_ids
        unknown_capabilities = rule.allowed_source_capabilities - known_capabilities
        next if unknown.empty? && unknown_capabilities.empty?

        raise InvalidManifest,
          "#{rule.source}: unknown allowed sources: " \
          "applications=#{unknown.join(', ')} capabilities=#{unknown_capabilities.join(', ')}"
      end
    end

    def validate_safe_get_paths!
      @route_rules.select { |rule| rule.safe_get_path.present? }.each do |rule|
        recovery = resolve(path: rule.safe_get_path, method: "GET")
        next if recovery && %w[document inertia_page].include?(recovery.kind)

        raise InvalidManifest,
          "#{rule.source}: safe_get_path #{rule.safe_get_path.inspect} must resolve to a GET document or Inertia page"
      end
    end

    def validate_launchers!
      @launchers.group_by(&:path).each do |path, candidates|
        duplicate_priority = candidates
          .group_by(&:priority)
          .find { |_priority, launchers| launchers.length > 1 }
        if duplicate_priority
          priority, launchers = duplicate_priority
          raise InvalidManifest,
            "launcher #{path.inspect} has duplicate priority #{priority}: " \
            "#{launchers.map(&:source).join(', ')}"
        end

        route_match = resolve(path:, method: "GET")
        unless route_match&.kind == "document"
          raise InvalidManifest,
            "launcher #{path.inspect} must have a canonical GET document route"
        end
      end
      @launchers.sort_by! { |launcher| [ launcher.path, -launcher.priority, launcher.application_id ] }
    end

    def validate_application_resources!
      adapter_claims = {}
      applications.each do |descriptor|
        %i[component_prefixes component_names styles locales error_boundaries capabilities].each do |field|
          values = descriptor.public_send(field)
          duplicate = values.group_by(&:itself).find { |_value, copies| copies.length > 1 }&.first
          if duplicate
            raise InvalidManifest,
              "#{descriptor.source}: duplicate #{field.to_s.singularize} #{duplicate.inspect}"
          end
        end

        if descriptor.renderer_adapters.length > 1
          raise InvalidManifest,
            "#{descriptor.source}: multiple exclusive renderer adapters are not allowed"
        end
        if descriptor.id != "website" && descriptor.renderer_adapters.any?
          raise InvalidManifest, "#{descriptor.source}: only Website may declare a renderer adapter"
        end
        if descriptor.id != "website" && descriptor.ui_adapter != "mcweb_ui"
          raise InvalidManifest, "#{descriptor.source}: #{descriptor.id} must use the mcweb_ui adapter"
        end
        if descriptor.id == "website"
          renderer = descriptor.renderer
          contribution = renderer&.contribution_id && descriptor.contributions.find do |item|
            item.id == renderer.contribution_id
          end
          valid_base = renderer&.contribution_id.nil? &&
            renderer&.product_owner == descriptor.product_owner &&
            renderer&.runtime_owner == descriptor.runtime_owner
          valid_contribution = contribution &&
            contribution.product_owner == renderer.product_owner &&
            contribution.runtime_owner == renderer.runtime_owner
          unless renderer && renderer.adapter == descriptor.renderer_adapters.first &&
              renderer.runtime_owner == descriptor.runtime_owner &&
              (valid_base || valid_contribution)
            raise InvalidManifest, "#{descriptor.source}: Website renderer identity is inconsistent"
          end
        end

        accessory_claims = {}
        descriptor.contributions.each do |contribution|
          if contribution.draft_contract &&
              !descriptor.capabilities.include?(contribution.draft_contract.capability)
            raise InvalidManifest,
              "#{contribution.source}: draft capability " \
              "#{contribution.draft_contract.capability.inspect} is not declared by #{descriptor.id}"
          end

          contribution.navigation.each do |group|
            group.items.each do |item|
              route = resolve(path: item.href, method: "GET")
              valid = route&.application_id == descriptor.id &&
                route.kind == "inertia_page" &&
                route.rule.contribution_id == contribution.id
              next if valid

              raise InvalidManifest,
                "#{contribution.source}: navigation href #{item.href.inspect} " \
                "is not an owned contribution page"
            end
          end

          contribution.accessories.each do |accessory|
            previous = accessory_claims[accessory]
            if previous
              raise InvalidManifest,
                "#{contribution.source}: runtime accessory #{accessory.inspect} " \
                "is already owned by #{previous.source}"
            end
            accessory_claims[accessory] = contribution
          end

          next unless contribution.adapter_module

          previous = adapter_claims[contribution.adapter_module]
          if previous
            raise InvalidManifest,
              "#{contribution.source}: adapter module #{contribution.adapter_module.inspect} " \
              "is already owned by #{previous.source}"
          end
          adapter_claims[contribution.adapter_module] = contribution
          unless descriptor.adapter_modules.include?(contribution.adapter_module)
            raise InvalidManifest,
              "#{contribution.source}: adapter module is missing from #{descriptor.id} runtime closure"
          end
        end

        declared_modules = descriptor.contributions.filter_map(&:adapter_module)
        unexpected_modules = descriptor.adapter_modules - declared_modules
        if unexpected_modules.any?
          raise InvalidManifest,
            "#{descriptor.source}: adapter modules have no contribution owner: " \
            "#{unexpected_modules.join(', ')}"
        end
      end
    end

    def freeze_registry!
      seen = {}
      [ @applications_by_id, @applications, @route_rules, @component_claims, @launchers ]
        .each { |value| deep_freeze(value, seen) }
    end

    def deep_freeze(value, seen)
      return value if value.nil? || value == true || value == false || value.is_a?(Numeric)
      return value if seen[value.object_id]

      seen[value.object_id] = true
      case value
      when Hash
        value.each { |key, child| deep_freeze(key, seen); deep_freeze(child, seen) }
      when Array
        value.each { |child| deep_freeze(child, seen) }
      when Struct
        value.each_pair { |_field, child| deep_freeze(child, seen) }
      end
      value.freeze
    end

    def validate_schema_version!(data, source)
      version = data["schema_version"]
      return if version == SCHEMA_VERSION

      raise InvalidManifest,
        "#{source}: schema_version must be #{SCHEMA_VERSION}, got #{version.inspect}"
    end

    def assert_required_keys!(data, required, source)
      missing = required - data.keys
      return if missing.empty?

      raise InvalidManifest, "#{source}: missing required keys: #{missing.join(', ')}"
    end

    def assert_exact_keys!(data, allowed, source)
      unless data.is_a?(Hash)
        raise InvalidManifest, "#{source}: expected an object"
      end

      unknown = data.keys - allowed
      return if unknown.empty?

      raise InvalidManifest, "#{source}: unknown keys: #{unknown.join(', ')}"
    end

    def validate_identifier!(value, source, field:)
      candidate = value.to_s
      return candidate if candidate.match?(IDENTIFIER)

      raise InvalidManifest, "#{source}: invalid #{field} #{candidate.inspect}"
    end

    def validate_owner!(value, source, field:)
      candidate = value.to_s
      return candidate if candidate.match?(OWNER_IDENTIFIER)

      raise InvalidManifest, "#{source}: invalid #{field} #{candidate.inspect}"
    end

    def validate_entrypoint!(value, source)
      candidate = value.to_s
      return candidate if candidate.match?(/\A[a-z][a-z0-9-]*\z/)

      raise InvalidManifest, "#{source}: invalid entrypoint #{candidate.inspect}"
    end

    def validate_adapter_name!(value, source)
      candidate = value.to_s
      return candidate if candidate.match?(/\A[a-z][a-z0-9_.-]*\z/)

      raise InvalidManifest, "#{source}: invalid adapter name #{candidate.inspect}"
    end

    def validate_locale_key!(value, source)
      candidate = value.to_s
      return candidate if candidate.match?(/\A[a-z][A-Za-z0-9_-]*(?:\.[a-z][A-Za-z0-9_-]*)*\z/)

      raise InvalidManifest, "#{source}: invalid locale key #{candidate.inspect}"
    end

    def validate_adapter_module!(value, source, application_id)
      candidate = value.to_s.tr("\\", "/")
      application_root = "app/javascript/frontend-application-adapters/#{application_id}/"
      valid = candidate.match?(
        %r{\Aapp/javascript/frontend-application-adapters/[a-z0-9_./-]+\.ts\z}
      ) && candidate.start_with?(application_root) &&
        !candidate.include?("..") && !candidate.include?("//")
      return candidate if valid

      raise InvalidManifest, "#{source}: invalid adapter_module #{candidate.inspect}"
    end

    def validate_repository_path!(value, source, field)
      candidate = value.to_s.tr("\\", "/")
      segments = candidate.split("/")
      invalid = candidate.blank? || candidate.start_with?("/") || candidate.include?("//") ||
        candidate.include?(":") || segments.any? { |segment| segment.in?([ "", ".", ".." ]) } ||
        candidate.match?(/[\x00-\x1f\x7f]/)
      raise InvalidManifest, "#{source}: invalid #{field} #{candidate.inspect}" if invalid

      candidate
    end

    def validate_page_roots!(values, source)
      roots = Array(values).map do |value|
        candidate = validate_repository_path!(value, source, "page_roots")
        unless candidate.match?(%r{\A(?:[a-z][a-z0-9_-]*/)*app/javascript/pages\z})
          raise InvalidManifest, "#{source}: invalid page root #{candidate.inspect}"
        end
        candidate
      end
      ensure_unique!(roots, source, "page_roots")
      raise InvalidManifest, "#{source}: page_roots must not be empty" if roots.empty?

      roots
    end

    def validate_component_prefixes!(values, source, allow_empty: false)
      prefixes = Array(values).map { |value| validate_component_prefix!(value, source) }
      if prefixes.empty? && !allow_empty
        raise InvalidManifest, "#{source}: component_prefixes must not be empty"
      end
      ensure_unique!(prefixes, source, "component_prefixes")
    end

    def validate_component_prefix!(value, source)
      candidate = value.to_s
      return candidate if candidate.match?(COMPONENT_PREFIX)

      raise InvalidManifest, "#{source}: invalid component prefix #{candidate.inspect}"
    end

    def validate_component_names!(values, source)
      names = Array(values).map do |value|
        candidate = value.to_s
        invalid = candidate.blank? || candidate.start_with?("/") || candidate.end_with?("/") ||
          candidate.include?("\\") || candidate.include?("..") ||
          !candidate.match?(/\A[A-Z][A-Za-z0-9]*(?:\/[A-Z][A-Za-z0-9]*)*\z/)
        raise InvalidManifest, "#{source}: invalid component name #{candidate.inspect}" if invalid
        candidate
      end
      ensure_unique!(names, source, "component_names")
    end

    def validate_string_list!(values, source, field:, allow_empty: true)
      unless values.is_a?(Array)
        raise InvalidManifest, "#{source}: #{field} must be an array"
      end
      strings = values.map do |value|
        candidate = value.to_s
        if candidate.blank? || !candidate.match?(/\A[a-zA-Z][a-zA-Z0-9_.-]*\z/)
          raise InvalidManifest, "#{source}: invalid #{field} value #{candidate.inspect}"
        end
        candidate
      end
      if strings.empty? && !allow_empty
        raise InvalidManifest, "#{source}: #{field} must not be empty"
      end
      ensure_unique!(strings, source, field)
    end

    def validate_budget!(raw, source)
      expected = %w[
        representative_paths representative_components representative_entries
        max_initial_javascript_bytes max_initial_stylesheet_bytes
      ]
      assert_required_keys!(
        raw,
        %w[representative_paths max_initial_javascript_bytes],
        "#{source}#budget"
      )
      assert_exact_keys!(raw, expected, "#{source}#budget")
      paths = Array(raw.fetch("representative_paths")).map do |path|
        validate_literal_path!(path, "#{source}#budget", field: "representative_paths")
      end
      raise InvalidManifest, "#{source}#budget: representative_paths must not be empty" if paths.empty?
      has_components = raw.key?("representative_components")
      has_entries = raw.key?("representative_entries")
      if has_components == has_entries
        raise InvalidManifest,
          "#{source}#budget: declare exactly one representative component or entry list"
      end
      components = if has_components
        validate_component_names!(raw.fetch("representative_components"), "#{source}#budget")
      else
        []
      end
      entries = if has_entries
        validate_string_list!(
          raw.fetch("representative_entries"),
          "#{source}#budget",
          field: "representative_entries",
          allow_empty: false
        ).map do |entry|
          validate_repository_path!(entry, "#{source}#budget", "representative_entries")
        end
      else
        []
      end
      resources = has_components ? components : entries
      unless resources.length == paths.length
        raise InvalidManifest,
          "#{source}#budget: representative paths and resources must have equal length"
      end

      javascript = positive_integer!(
        raw.fetch("max_initial_javascript_bytes"),
        "#{source}#budget",
        "max_initial_javascript_bytes"
      )
      stylesheet = if raw.key?("max_initial_stylesheet_bytes")
        positive_integer!(
          raw.fetch("max_initial_stylesheet_bytes"),
          "#{source}#budget",
          "max_initial_stylesheet_bytes"
        )
      end
      {
        "representative_paths" => paths.freeze,
        "representative_components" => components.freeze,
        "representative_entries" => entries.freeze,
        "max_initial_javascript_bytes" => javascript,
        "max_initial_stylesheet_bytes" => stylesheet
      }.compact
    end

    def build_draft_contract(raw, source)
      contract_source = "#{source}#draft_contract"
      expected = %w[
        capability key_namespace version user_scoped resource_scoped
        offline_recovery clear_on_submit
      ]
      assert_required_keys!(raw, expected, contract_source)
      assert_exact_keys!(raw, expected, contract_source)
      version = positive_integer!(raw.fetch("version"), contract_source, "version")
      flags = %w[user_scoped resource_scoped offline_recovery clear_on_submit]
      unless flags.all? { |flag| raw[flag] == true }
        raise InvalidManifest,
          "#{contract_source}: user/resource scope, offline recovery, and clear_on_submit must be true"
      end

      DraftContract.new(
        capability: validate_adapter_name!(raw.fetch("capability"), contract_source),
        key_namespace: validate_adapter_name!(raw.fetch("key_namespace"), contract_source),
        version:,
        user_scoped: true,
        resource_scoped: true,
        offline_recovery: true,
        clear_on_submit: true
      )
    end

    def merge_application_budget!(target, contribution)
      stylesheet_limits = [
        target["max_initial_stylesheet_bytes"],
        contribution["max_initial_stylesheet_bytes"]
      ].compact
      target.replace(
        "representative_paths" => (
          target.fetch("representative_paths") + contribution.fetch("representative_paths")
        ).freeze,
        "representative_components" => (
          target.fetch("representative_components") + contribution.fetch("representative_components")
        ).freeze,
        "representative_entries" => (
          target.fetch("representative_entries") + contribution.fetch("representative_entries")
        ).freeze,
        "max_initial_javascript_bytes" => [
        target.fetch("max_initial_javascript_bytes"),
        contribution.fetch("max_initial_javascript_bytes")
        ].max,
        **(
          stylesheet_limits.any? ?
            { "max_initial_stylesheet_bytes" => stylesheet_limits.max } : {}
        )
      )
    end

    def positive_integer!(value, source, field)
      candidate = Integer(value, exception: false)
      return candidate if candidate&.positive?

      raise InvalidManifest, "#{source}: #{field} must be a positive integer"
    end

    def validate_methods!(values, source)
      methods = Array(values).map(&:to_s)
      if methods.empty? || methods.any? { |method| method != method.upcase } ||
          (methods - HTTP_METHODS).any?
        raise InvalidManifest, "#{source}: invalid HTTP methods #{methods.inspect}"
      end
      ensure_unique!(methods, source, "methods")
    end

    def validate_route_kind_methods!(kind, methods, source)
      if kind == "inertia_page" && (methods - %w[GET HEAD]).any?
        raise InvalidManifest, "#{source}: inertia_page permits only GET/HEAD"
      end
      if kind == "document" && (methods - %w[GET HEAD]).any?
        raise InvalidManifest, "#{source}: document permits only GET/HEAD"
      end
      if kind == "shared_action" && (methods & %w[GET HEAD]).any?
        raise InvalidManifest, "#{source}: shared_action must be non-GET"
      end
      return unless kind == "application_action" && (methods & %w[GET HEAD]).any?

      raise InvalidManifest, "#{source}: application_action must be non-GET"
    end

    def validate_route_pattern!(value, source)
      pattern = value.to_s
      validate_path_safety!(pattern, source, field: "pattern")
      if pattern.include?("***") || pattern.include?("?") || pattern.include?("#")
        raise InvalidManifest, "#{source}: invalid route pattern #{pattern.inspect}"
      end
      pattern
    end

    def validate_literal_path!(value, source, field:)
      path = value.to_s
      validate_path_safety!(path, source, field:)
      if path.include?("*") || path.include?("?") || path.include?("#")
        raise InvalidManifest, "#{source}: #{field} must be a literal relative path"
      end
      path
    end

    def validate_path_safety!(path, source, field:)
      invalid = path.blank? || !path.start_with?("/") || path.start_with?("//") ||
        path.include?("\\") || path.match?(/[\x00-\x1f\x7f]/)
      unless invalid
        begin
          decoded_segments = path.split("/").map { |segment| URI.decode_www_form_component(segment) }
          invalid = decoded_segments.any? do |segment|
            segment.in?([ ".", ".." ]) || segment.match?(/[\\\/\x00-\x1f\x7f]/)
          end
        rescue ArgumentError
          invalid = true
        end
      end
      raise InvalidManifest, "#{source}: invalid #{field} #{path.inspect}" if invalid
    end

    def compile_route_pattern(pattern)
      expression = +""
      index = 0
      while index < pattern.length
        if pattern[index, 2] == "**"
          expression << ".*"
          index += 2
        elsif pattern[index] == "*"
          expression << "[^/]*"
          index += 1
        else
          expression << Regexp.escape(pattern[index])
          index += 1
        end
      end
      Regexp.new("\\A#{expression}\\z")
    end

    def normalize_request_path(value)
      path = value.to_s
      validate_path_safety!(path, "request", field: "path")
      path
    end

    def normalize_component_name(value)
      component = value.to_s
      invalid = component.blank? || component.start_with?("/") || component.end_with?("/") ||
        component.include?("\\") || component.include?("..") ||
        component.match?(/[\x00-\x1f\x7f]/)
      if invalid
        raise ComponentBoundaryViolation, "invalid Inertia component name #{component.inspect}"
      end
      component
    end

    def component_claim_overlap?(left, right)
      return left.prefix == right.prefix if left.exact && right.exact
      return left.prefix.start_with?(right.prefix) if left.exact
      return right.prefix.start_with?(left.prefix) if right.exact

      left.prefix.start_with?(right.prefix) || right.prefix.start_with?(left.prefix)
    end

    def component_claim_parent_child(left, right)
      return [ right, left ] if left.exact && !right.exact
      return [ left, right ] if right.exact && !left.exact

      left.prefix.length < right.prefix.length ? [ left, right ] : [ right, left ]
    end

    def ensure_unique!(values, source, field)
      duplicate = values.group_by(&:itself).find { |_value, copies| copies.length > 1 }&.first
      raise InvalidManifest, "#{source}: duplicate #{field} value #{duplicate.inspect}" if duplicate

      values
    end

    def read_json(path)
      JSON.parse(Pathname(path).read(encoding: "UTF-8"))
    rescue Errno::ENOENT
      raise InvalidManifest, "missing frontend application manifest: #{relative_source(path)}"
    rescue JSON::ParserError => error
      raise InvalidManifest, "#{relative_source(path)}: invalid JSON: #{error.message}"
    end

    def relative_source(path)
      Pathname(path).relative_path_from(@root).to_s.tr("\\", "/")
    rescue ArgumentError
      path.to_s
    end
  end
end
