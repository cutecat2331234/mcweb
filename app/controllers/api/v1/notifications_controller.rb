# frozen_string_literal: true

module Api
  module V1
    # Notifications for the user the API key acts as. Requires a bound user.
    class NotificationsController < BaseController
      before_action :require_bound_user!
      skip_before_action :require_read_scope!, only: %i[read read_all destroy]
      before_action :require_writer!, only: %i[read read_all destroy]
      before_action :set_notification, only: %i[read destroy]

      # GET /api/v1/notifications?unread=true
      def index
        scope = api_user.notifications.recent
        scope = scope.unread if params[:unread].to_s == "true"

        pagy, notifications = api_paginate(scope)
        notification_access = Account::NotificationAccess.new(
          user: api_user,
          notifications: notifications
        )

        render json: {
          data: notifications.map { |n| serialize_notification(n, notification_access: notification_access) },
          meta: pagination_meta(pagy).merge(unread_count: api_user.notifications.unread.count)
        }
      end

      # POST /api/v1/notifications/:id/read
      def read
        @notification.mark_read!
        render json: { data: serialize_notification(@notification) }
      end

      # POST /api/v1/notifications/read_all
      def read_all
        count = api_user.notifications.unread.update_all(read_at: Time.current)
        render json: { data: { marked_read: count } }
      end

      # DELETE /api/v1/notifications/:id
      def destroy
        @notification.destroy!
        head :no_content
      end

      private

      def set_notification
        @notification = api_user.notifications.find(params[:id])
      end

      def serialize_notification(notification, notification_access: nil)
        access = notification_access || Account::NotificationAccess.new(
          user: api_user,
          notifications: [ notification ]
        )
        visible = access.visible?(notification)

        {
          id: notification.id,
          type: notification.notification_type,
          title: visible ? notification.title : nil,
          body: visible ? notification.body : nil,
          url: visible ? notification.destination_path : nil,
          content_available: visible,
          read: notification.read?,
          created_at: notification.created_at&.iso8601
        }
      end
    end
  end
end
