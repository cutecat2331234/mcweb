# frozen_string_literal: true

module Admin
  module System
    class RateLimitsController < BaseController
      before_action -> { require_permission("system.settings.manage") }
      before_action :disable_caching

      def show
        render_page
      end

      def update
        submitted = submitted_policies
        result = Administration::UpdateAbuseRateLimitPolicies.call(policies: submitted)

        unless result.success?
          render_page(
            form_values: form_values_from(submitted),
            form_errors: serialized_errors(result.errors),
            status: :unprocessable_entity
          )
          return
        end

        audit_changes(result.value) if result.value[:changed_paths].any?

        redirect_to admin_system_rate_limits_path,
          notice: t("mcweb.flash.rate_limit_settings_saved")
      end

      private

      def render_page(form_values: nil, form_errors: {}, status: :ok)
        metrics = Administration::AbuseRateLimitMetrics.call.value

        render inertia: "Admin/System/RateLimits/Show",
          props: {
            rows: metrics.fetch(:rows),
            summary: metrics.fetch(:summary),
            formValues: form_values || form_values_from_rows(metrics.fetch(:rows)),
            formErrors: form_errors,
            constraints: {
              limit: {
                min: Administration::AbuseRateLimit.minimum_for(:limit),
                max: Administration::AbuseRateLimit.maximum_for(:limit)
              },
              windowSeconds: {
                min: Administration::AbuseRateLimit.minimum_for(:window_seconds),
                max: Administration::AbuseRateLimit.maximum_for(:window_seconds)
              }
            },
            updateUrl: admin_system_rate_limits_path
          },
          status: status
      end

      def submitted_policies
        source = params[:policies]
        return {} unless source.respond_to?(:dig)

        Administration::AbuseRateLimit::POLICIES.each_with_object({}) do |(action, dimensions), policies|
          policies[action.to_s] = dimensions.each_key.each_with_object({}) do |dimension, values|
            submitted = source.dig(action.to_s, dimension.to_s)
            values[dimension.to_s] =
              if submitted.respond_to?(:permit)
                submitted.permit(:limit, :window_seconds).to_h
              else
                {}
              end
          end
        end
      end

      def form_values_from_rows(rows)
        rows.each_with_object({}) do |row, policies|
          action = row.fetch(:action)
          dimension = row.fetch(:dimension)
          policies[action] ||= {}
          policies[action][dimension] = {
            limit: row.fetch(:limit),
            window_seconds: row.fetch(:window_seconds)
          }
        end
      end

      def form_values_from(submitted)
        submitted.each_with_object({}) do |(action, dimensions), policies|
          policies[action] = dimensions.each_with_object({}) do |(dimension, values), result|
            result[dimension] = {
              limit: display_integer(values["limit"]),
              window_seconds: display_integer(values["window_seconds"])
            }
          end
        end
      end

      def display_integer(value)
        Integer(value.to_s, 10, exception: false)
      end

      def serialized_errors(errors)
        errors.transform_values { |messages| Array(messages).join(" ") }
      end

      def audit_changes(changes)
        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.rate_limit_settings_updated",
          metadata: { changed_paths: changes.fetch(:changed_paths) },
          before_state: changes.fetch(:before_state),
          after_state: changes.fetch(:after_state),
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end

      def disable_caching
        response.set_header("Cache-Control", "no-store")
      end
    end
  end
end
