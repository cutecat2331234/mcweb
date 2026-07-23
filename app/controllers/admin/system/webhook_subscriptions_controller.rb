# frozen_string_literal: true

module Admin
  module System
    # Manage generic outbound webhook subscriptions driven by the Mcweb::Events bus.
    class WebhookSubscriptionsController < BaseController
      before_action -> { require_permission("admin.access") }
      before_action :set_subscription, only: %i[edit update destroy]

      def index
        subscriptions = Administration::WebhookSubscription.order(created_at: :desc).limit(200)

        render inertia: "Admin/System/WebhookSubscriptions/Index", props: {
          title: t("mcweb.admin.webhook_subscriptions.title"),
          subtitle: t("mcweb.admin.webhook_subscriptions.subtitle"),
          newUrl: new_admin_system_webhook_subscription_path,
          subscriptions: subscriptions.map { |s| serialize_subscription(s) }
        }
      end

      def new
        render inertia: "Admin/System/WebhookSubscriptions/Form", props: form_props(Administration::WebhookSubscription.new(event: "*"))
      end

      def create
        subscription = Administration::WebhookSubscription.new(subscription_params.merge(created_by: current_user))
        if subscription.save
          redirect_to admin_system_webhook_subscriptions_path, notice: t("mcweb.flash.webhook_subscription_created")
        else
          render inertia: "Admin/System/WebhookSubscriptions/Form", props: form_props(subscription), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/System/WebhookSubscriptions/Form", props: form_props(@subscription, editing: true)
      end

      def update
        if @subscription.update(subscription_params)
          redirect_to admin_system_webhook_subscriptions_path, notice: t("mcweb.flash.webhook_subscription_updated")
        else
          render inertia: "Admin/System/WebhookSubscriptions/Form", props: form_props(@subscription, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @subscription.destroy!
        redirect_to admin_system_webhook_subscriptions_path, notice: t("mcweb.flash.webhook_subscription_deleted")
      end

      private

      def set_subscription
        @subscription = Administration::WebhookSubscription.find(params[:id])
      end

      def subscription_params
        params.require(:webhook_subscription).permit(:name, :url, :event, :secret, :active)
      end

      def serialize_subscription(subscription)
        {
          id: subscription.id,
          name: subscription.name,
          url: subscription.url,
          event: subscription.event,
          active: subscription.active && subscription.disabled_at.nil?,
          lastStatus: subscription.last_status,
          lastDeliveredAt: subscription.last_delivered_at ? l(subscription.last_delivered_at, format: :short) : nil,
          failureCount: subscription.failure_count,
          editUrl: edit_admin_system_webhook_subscription_path(subscription)
        }
      end

      def form_props(subscription, editing: false)
        {
          title: editing ? t("mcweb.admin.webhook_subscriptions.form_edit") : t("mcweb.admin.webhook_subscriptions.form_new"),
          subscription: {
            name: subscription.name || "",
            url: subscription.url || "",
            event: subscription.event || "*",
            secret: subscription.secret || "",
            active: subscription.active.nil? ? true : subscription.active
          },
          events: Administration::WebhookSubscription.valid_events,
          submitUrl: editing ? admin_system_webhook_subscription_path(subscription) : admin_system_webhook_subscriptions_path,
          method: editing ? "patch" : "post",
          backUrl: admin_system_webhook_subscriptions_path,
          deleteUrl: editing ? admin_system_webhook_subscription_path(subscription) : nil
        }
      end
    end
  end
end
