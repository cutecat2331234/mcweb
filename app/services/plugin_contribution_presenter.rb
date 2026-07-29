# frozen_string_literal: true

class PluginContributionPresenter
  SURFACES = %w[public admin].freeze
  PAGE_BLOCK_TYPES = %w[stat text alert links description_list].freeze
  ALERT_TONES = %w[info success warning error].freeze
  SLOT_KINDS = %w[card action field].freeze

  def initialize(user:, locale:, path:)
    @user = user
    @locale = locale.to_s
    @path = normalize_path(path)
  end

  def shared_payload
    {
      navigation: {
        public: navigation("public"),
        admin: navigation("admin")
      },
      ui_slots: ui_slots
    }.freeze
  rescue StandardError
    { navigation: { public: [], admin: [] }, ui_slots: [] }.freeze
  end

  def translation_overrides
    phrase_map.dup.freeze
  rescue StandardError
    {}.freeze
  end

  def page(surface:)
    surface = normalize_surface(surface)
    entry = contributions("page").find do |candidate|
      payload = candidate.payload
      payload["surface"] == surface &&
        normalize_path(payload["path"]) == @path &&
        visible?(payload)
    end
    return unless entry

    serialize_page(entry)
  rescue StandardError
    nil
  end

  private

  def contributions(type)
    return [] unless defined?(Mcweb::Plugins) && Mcweb::Plugins.respond_to?(:contributions)

    Array(Mcweb::Plugins.contributions(type:))
  end

  def navigation(surface)
    surface = normalize_surface(surface)
    contributions("navigation").filter_map do |entry|
      payload = entry.payload
      next unless payload["surface"] == surface && visible?(payload)

      {
        id: entry.id,
        plugin_id: entry.plugin_id,
        position: payload["position"],
        label: phrase(payload["label_phrase"]),
        href: payload["href"],
        icon: payload["icon"].to_s.presence
      }.compact.freeze
    end.freeze
  end

  def ui_slots
    contributions("ui_slot").filter_map do |entry|
      payload = entry.payload
      target = payload["target"].to_s
      next if target.blank?
      next unless path_matches_target?(target)
      next unless visible?(payload)
      next unless SLOT_KINDS.include?(payload["kind"])

      {
        id: entry.id,
        plugin_id: entry.plugin_id,
        slot: payload["slot"],
        kind: payload["kind"],
        title: phrase(payload["title_phrase"]),
        target:,
        schema: serialize_slot_schema(payload["schema"])
      }.freeze
    end.freeze
  end

  def serialize_page(entry)
    payload = entry.payload
    {
      id: entry.id,
      plugin_id: entry.plugin_id,
      surface: payload["surface"],
      path: payload["path"],
      title: phrase(payload["title_phrase"]),
      description: payload["description_phrase"] ? phrase(payload["description_phrase"]) : nil,
      blocks: Array(payload["blocks"]).filter_map { |block| serialize_page_block(block) }
    }.freeze
  end

  def serialize_page_block(value)
    return unless value.is_a?(Hash)

    block = value.stringify_keys
    type = block["type"].to_s
    return unless PAGE_BLOCK_TYPES.include?(type)

    base = {
      type:,
      title: phrase_optional(block["title_phrase"]),
      tone: normalize_tone(block["tone"])
    }.compact
    case type
    when "stat"
      label = phrase_optional(block["label_phrase"])
      value = safe_scalar(block["value"])
      return unless label && !value.nil?

      base.merge(label:, value:).freeze
    when "text"
      body = phrase_optional(block["body_phrase"])
      return unless body

      base.merge(body:).freeze
    when "alert"
      title = phrase_optional(block["title_phrase"])
      return unless title

      base.merge(title:, body: phrase_optional(block["body_phrase"])).compact.freeze
    when "links"
      links = Array(block["items"]).filter_map { |item| serialize_link(item) }
      return if links.empty?

      base.merge(items: links).freeze
    when "description_list"
      items = Array(block["items"]).filter_map { |item| serialize_description(item) }
      return if items.empty?

      base.merge(items:).freeze
    end
  end

  def serialize_link(value)
    return unless value.is_a?(Hash)

    item = value.stringify_keys
    href = item["href"].to_s
    return unless safe_internal_path?(href)

    label = phrase_optional(item["label_phrase"])
    { label:, href: }.freeze if label
  end

  def serialize_description(value)
    return unless value.is_a?(Hash)

    item = value.stringify_keys
    label = phrase_optional(item["label_phrase"])
    value = safe_scalar(item["value"])
    { label:, value: }.freeze if label && !value.nil?
  end

  def serialize_slot_schema(value)
    return {}.freeze unless value.is_a?(Hash)

    schema = value.stringify_keys
    href = schema["href"].to_s
    {
      description: phrase_optional(schema["description_phrase"]),
      value: safe_scalar(schema["value"]),
      href: safe_internal_path?(href) ? href : nil,
      action_label: phrase_optional(schema["action_label_phrase"]),
      tone: normalize_tone(schema["tone"])
    }.compact.freeze
  end

  def phrase_map
    @phrase_map ||= begin
      grouped = contributions("translation").group_by { |entry| entry.payload["locale"].to_s }
      fallback_locales.each_with_object({}) do |locale, result|
        Array(grouped[locale]).each do |entry|
          result.merge!(entry.payload.fetch("phrases", {}))
        end
      end.freeze
    end
  end

  def fallback_locales
    locales = [ "en" ]
    language = @locale.split("-", 2).first
    locales << language if language.present?
    locales << @locale if @locale.present?
    locales.uniq
  end

  def phrase(key)
    phrase_map[key.to_s].presence || humanized_phrase_fallback(key)
  end

  def phrase_optional(key)
    key.present? ? phrase(key) : nil
  end

  def humanized_phrase_fallback(key)
    key.to_s.split(".").last.to_s.tr("_", " ").humanize
  end

  def visible?(payload)
    permission = payload["permission"].to_s
    return true if permission.blank?
    return false unless @user&.persisted?

    @user.permission?(permission)
  rescue StandardError
    false
  end

  def normalize_surface(value)
    surface = value.to_s
    raise ArgumentError, "unsupported plugin contribution surface" unless SURFACES.include?(surface)

    surface
  end

  def normalize_path(value)
    path = value.to_s.split(/[?#]/, 2).first
    path = "/#{path}" unless path.start_with?("/")
    path = path.chomp("/") unless path == "/"
    path
  end

  def path_matches_target?(target)
    normalized = normalize_path(target)
    @path == normalized || @path.start_with?("#{normalized}/")
  end

  def safe_internal_path?(value)
    value.start_with?("/") &&
      !value.start_with?("//") &&
      !value.include?("\\") &&
      !value.include?("..") &&
      !value.match?(/[\u0000-\u001f]/)
  end

  def safe_scalar(value)
    case value
    when String
      value.to_s.slice(0, 10_000)
    when Numeric, true, false
      value
    end
  end

  def normalize_tone(value)
    tone = value.to_s
    ALERT_TONES.include?(tone) ? tone : nil
  end
end
