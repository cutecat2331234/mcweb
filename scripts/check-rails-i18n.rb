# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("..", __dir__)
LOCALE_FILES = Dir[File.join(ROOT, "config/locales/**/*.{yml,yaml}")].sort.freeze
BUSINESS_SCOPE = "mcweb"
PLACEHOLDER_PATTERN = /%(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|<([A-Za-z_][A-Za-z0-9_]*)>)/.freeze

def deep_merge(left, right)
  left.merge(right) do |_key, left_value, right_value|
    if left_value.is_a?(Hash) && right_value.is_a?(Hash)
      deep_merge(left_value, right_value)
    else
      right_value
    end
  end
end

def flatten(value, prefix = nil, result = {})
  case value
  when Hash
    value.each do |key, entry|
      full_key = [ prefix, key ].compact.join(".")
      flatten(entry, full_key, result)
    end
  when Array
    value.each_with_index do |entry, index|
      flatten(entry, "#{prefix}[#{index}]", result)
    end
  when String
    result[prefix] = value
  else
    raise "#{prefix || "locale"} must be a string, got #{value.class}"
  end
  result
end

def placeholders(message)
  message.scan(PLACEHOLDER_PATTERN).map { |pair| pair.compact.fetch(0) }.sort
end

def report(label, values)
  return if values.empty?

  warn "#{label}:"
  values.each { |value| warn "  - #{value}" }
end

locales = LOCALE_FILES.each_with_object({}) do |filename, merged|
  document = YAML.safe_load_file(
    filename,
    permitted_classes: [ Symbol ],
    aliases: true
  )
  next unless document.is_a?(Hash)

  document.each do |locale, messages|
    locale = locale.to_s
    merged[locale] = deep_merge(merged.fetch(locale, {}), messages.to_h)
  end
end

english = flatten(locales.fetch("en").fetch(BUSINESS_SCOPE), BUSINESS_SCOPE)
chinese = flatten(locales.fetch("zh-CN").fetch(BUSINESS_SCOPE), BUSINESS_SCOPE)
missing_chinese = (english.keys - chinese.keys).sort
missing_english = (chinese.keys - english.keys).sort
placeholder_mismatches = (english.keys & chinese.keys).select do |key|
  placeholders(english.fetch(key)) != placeholders(chinese.fetch(key))
end.sort

report("Missing from Rails zh-CN", missing_chinese)
report("Missing from Rails en", missing_english)
report("Rails interpolation placeholders differ", placeholder_mismatches)

if missing_chinese.any? || missing_english.any? || placeholder_mismatches.any?
  exit 1
end

puts "Rails locale parity passed (#{english.size} #{BUSINESS_SCOPE} keys)."
