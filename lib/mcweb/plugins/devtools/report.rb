# frozen_string_literal: true

require "json"

module Mcweb
  module Plugins
    module Devtools
      Report = Data.define(:command, :ok, :data, :warnings, :errors) do
        SCHEMA_VERSION = "1"

        def self.success(command, data: {}, warnings: [])
          new(
            command: command.to_s.freeze,
            ok: true,
            data: immutable(data),
            warnings: immutable(Array(warnings)),
            errors: [].freeze
          )
        end

        def self.failure(command, errors:, data: {}, warnings: [])
          new(
            command: command.to_s.freeze,
            ok: false,
            data: immutable(data),
            warnings: immutable(Array(warnings)),
            errors: immutable(Array(errors))
          )
        end

        def self.immutable(value)
          JSON.parse(JSON.generate(value), freeze: true)
        end
        private_class_method :immutable

        def ok?
          ok
        end

        def to_h
          {
            schema_version: SCHEMA_VERSION,
            command:,
            ok:,
            data:,
            warnings:,
            errors:
          }.freeze
        end
      end
    end
  end
end
