# frozen_string_literal: true

module Minecraft
  class NodeOperationDigest
    def self.call(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def self.canonicalize(value)
      case value
      when Hash
        value.to_h.each_with_object({}) do |(key, child), sorted|
          sorted[key.to_s] = canonicalize(child)
        end.sort.to_h
      when Array
        value.map { |child| canonicalize(child) }
      else
        value
      end
    end

    private_class_method :canonicalize
  end
end
