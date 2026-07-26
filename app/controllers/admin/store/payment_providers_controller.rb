# frozen_string_literal: true

module Admin
  module Store
    class PaymentProvidersController < BaseController
      before_action -> { require_permission(Payments::UpdateProviderConfiguration::PERMISSION) }
      before_action -> { require_permission(Payments::TestProviderConnection::PERMISSION) },
        only: :test_connection

      def show
        config = Payments::ProviderConfig.find_or_initialize_by(provider: "stripe")
        webhook_result = Payments::StripeWebhookConfigurationCheck.call(config: config)
        connection_test_allowed = current_user.permission?(
          Payments::TestProviderConnection::PERMISSION
        )
        connection_test_token =
          if connection_test_allowed && config.persisted? && config.configuration_complete?
            Payments::ProviderConnectionTestToken.issue(config)
          end

        response.set_header("Cache-Control", "no-store")
        render inertia: "Admin/Store/PaymentProviders/Show", props: {
          providerConfig: Payments::ProviderConfigurationSerializer.call(
            config: config,
            webhook_check: webhook_result.value,
            connection_test_token: connection_test_token,
            connection_test_allowed: connection_test_allowed
          ),
          updateUrl: admin_store_payment_providers_path,
          testConnectionUrl: admin_store_payment_provider_connection_test_path
        }
      end

      def update
        result = Payments::UpdateProviderConfiguration.call(
          actor: current_user,
          attributes: provider_config_params,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        if result.success?
          redirect_to admin_store_payment_providers_path,
            notice: t(
              "mcweb.flash.payment_provider_configuration_updated",
              default: "Payment-provider configuration updated."
            )
        else
          redirect_to admin_store_payment_providers_path, alert: result.error
        end
      end

      def test_connection
        result = Payments::TestProviderConnection.call(
          actor: current_user,
          token: params[:token],
          confirmation: params[:confirmation],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        if result.success?
          redirect_to admin_store_payment_providers_path,
            notice: t(
              "mcweb.flash.payment_provider_connection_test_succeeded",
              default: "Stripe connection test succeeded."
            )
        else
          redirect_to admin_store_payment_providers_path, alert: result.error
        end
      end

      private

      def provider_config_params
        params.require(:provider_config).permit(
          :enabled,
          :mode,
          :secret_key,
          :webhook_secret,
          :clear_secret_key,
          :clear_webhook_secret
        )
      end
    end
  end
end
