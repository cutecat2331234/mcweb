# frozen_string_literal: true

module Mcweb
  module OperationsDurableEnqueueRegistrarConfig
    KEY = :operations_durable_enqueue_registrars
    CONTAINER_ERROR = "operations_durable_enqueue_registrars_must_be_array"
    CONFIG_ERROR = "operations_durable_enqueue_config_invalid"
    STORE_ERROR = "operations_durable_enqueue_config_store_invalid"
    REGISTRAR_ERROR = "operations_durable_enqueue_registrar_must_be_callable"
    DUPLICATE_ERROR = "operations_durable_enqueue_registrar_duplicate"
    FROZEN_ERROR = "operations_durable_enqueue_registrars_frozen"

    module_function

    def initialize!(custom_config)
      store = configuration_store!(custom_config)
      registrars = store[KEY]
      registrars = store[KEY] = [] if registrars.nil?
      validate!(registrars)
    end

    def register!(custom_config, registrar)
      registrars = fetch!(custom_config)
      raise FrozenError, FROZEN_ERROR if registrars.frozen?

      validate_registrar!(registrar)
      raise ArgumentError, DUPLICATE_ERROR if registrars.any? { |entry| entry.equal?(registrar) }

      registrars << registrar
      registrar
    end

    def freeze_and_fetch!(custom_config)
      fetch!(custom_config).freeze
    end

    def fetch!(custom_config)
      store = configuration_store!(custom_config)
      validate!(store[KEY])
    end
    private_class_method :fetch!

    def configuration_store!(custom_config)
      expected_type = Rails::Application::Configuration::Custom
      raise TypeError, CONFIG_ERROR unless custom_config.is_a?(expected_type)
      raise TypeError, STORE_ERROR unless custom_config.instance_variable_defined?(:@configurations)

      store = custom_config.instance_variable_get(:@configurations)
      raise TypeError, STORE_ERROR unless store.is_a?(Hash)

      store
    end
    private_class_method :configuration_store!

    def validate!(registrars)
      raise TypeError, CONTAINER_ERROR unless registrars.is_a?(Array)

      seen = {}.compare_by_identity
      registrars.each do |registrar|
        validate_registrar!(registrar)
        raise ArgumentError, DUPLICATE_ERROR if seen.key?(registrar)

        seen[registrar] = true
      end
      registrars
    end
    private_class_method :validate!

    def validate_registrar!(registrar)
      raise TypeError, REGISTRAR_ERROR unless registrar.respond_to?(:call)
    end
    private_class_method :validate_registrar!
  end
end
