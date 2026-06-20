# frozen_string_literal: true

module Community
  class SectionPrefixes
    def self.normalize(raw)
      Array(raw).filter_map do |item|
        case item
        when String
          name = item.strip
          next if name.blank?

          { "name" => name, "color_hex" => nil }
        when Hash
          name = (item["name"] || item[:name]).to_s.strip
          next if name.blank?

          color = (item["color_hex"] || item[:color_hex]).to_s.strip.presence
          { "name" => name, "color_hex" => color }
        end
      end
    end

    def self.names(raw)
      normalize(raw).map { |entry| entry["name"] }
    end

    def self.color_for(raw, name)
      return if name.blank?

      normalize(raw).find { |entry| entry["name"] == name }&.dig("color_hex")
    end

    def self.parse_form(text)
      text.to_s.lines.filter_map do |line|
        line = line.strip
        next if line.blank?

        if line.include?("|")
          name, color = line.split("|", 2).map(&:strip)
          next if name.blank?

          { "name" => name, "color_hex" => normalize_color(color) }
        else
          { "name" => line, "color_hex" => nil }
        end
      end
    end

    def self.to_form_text(definitions)
      normalize(definitions).map do |entry|
        color = entry["color_hex"]
        color.present? ? "#{entry['name']}|#{color}" : entry["name"]
      end.join("\n")
    end

    def self.serialize_options(raw)
      normalize(raw).map do |entry|
        {
          name: entry["name"],
          color_hex: entry["color_hex"],
          label: entry["name"]
        }
      end
    end

    def self.normalize_color(value)
      hex = value.to_s.strip
      return if hex.blank?

      hex = "##{hex}" unless hex.start_with?("#")
      hex
    end

    private_class_method :normalize_color
  end
end
