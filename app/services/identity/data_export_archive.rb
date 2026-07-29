# frozen_string_literal: true

require "zip"

module Identity
  class DataExportArchive < ApplicationService
    PROFILE_FIELDS = %w[
      public_id email username display_name bio locale time_zone created_at updated_at
      email_verified email_verified_at status account_type deleted_at
    ].freeze
    TOPIC_FIELDS = %w[public_id title status created_at updated_at deleted_at forum_section_id].freeze
    POST_FIELDS = %w[id forum_topic_id body status post_type created_at updated_at deleted_at edited_at].freeze
    MESSAGE_FIELDS = %w[id forum_conversation_id body created_at updated_at edited_at deleted_at].freeze
    NOTIFICATION_FIELDS = %w[id notification_type title body metadata read_at created_at].freeze
    UPLOAD_FIELDS = %w[
      public_id kind status scan_status content_type byte_size created_at linked_at cleaned_at
      manual_review_status manual_reviewed_at manual_review_revoked_at
    ].freeze
    ORDER_FIELDS = %w[
      public_id order_number status currency subtotal_cents discount_cents total_cents
      store_credit_amount_cents created_at updated_at
    ].freeze
    MEMBERSHIP_FIELDS = %w[id store_membership_type_id status source starts_at expires_at created_at].freeze
    ENTITLEMENT_FIELDS = %w[id store_product_id starts_at expires_at revoked_at created_at].freeze

    def initialize(user:, generated_at: Time.current)
      @user = user
      @generated_at = generated_at
    end

    def call
      documents = export_documents
      archive = Zip::OutputStream.write_buffer do |zip|
        documents.each do |path, payload|
          zip.put_next_entry(path)
          zip.write(JSON.pretty_generate(payload))
        end
      end
      archive.rewind

      ServiceResult.success(
        io: archive,
        manifest: documents.transform_values { |payload| record_count(payload) }
      )
    rescue StandardError => e
      Rails.logger.error("data export generation failed: #{e.class}")
      ServiceResult.failure(error: "data_export_generation_failed", code: "data_export_generation_failed")
    end

    private

    def export_documents
      {
        "manifest.json" => {
          schema_version: 1,
          generated_at: @generated_at.iso8601,
          user_public_id: @user.public_id,
          files: %w[
            profile.json forum/topics.json forum/posts.json forum/messages.json
            notifications.json uploads.json commerce/orders.json commerce/memberships.json
            commerce/entitlements.json commerce/shipping-addresses.json
          ]
        },
        "profile.json" => record(@user, PROFILE_FIELDS),
        "forum/topics.json" => records(Community::Topic.where(user: @user).order(:id), TOPIC_FIELDS),
        "forum/posts.json" => records(Community::Post.where(user: @user).order(:id), POST_FIELDS),
        "forum/messages.json" => records(Community::Message.where(user: @user).order(:id), MESSAGE_FIELDS),
        "notifications.json" => records(Notification.where(user: @user).order(:id), NOTIFICATION_FIELDS),
        "uploads.json" => records(Community::Upload.where(user: @user).order(:id), UPLOAD_FIELDS),
        "commerce/orders.json" => records(Commerce::Order.where(user: @user).order(:id), ORDER_FIELDS),
        "commerce/memberships.json" => records(Commerce::UserMembership.where(user: @user).order(:id), MEMBERSHIP_FIELDS),
        "commerce/entitlements.json" => records(Commerce::UserEntitlement.where(user: @user).order(:id), ENTITLEMENT_FIELDS),
        "commerce/shipping-addresses.json" => shipping_addresses
      }
    end

    def shipping_addresses
      Commerce::ShippingAddress.where(user: @user).order(:id).map do |address|
        address.to_address_hash.merge(
          "id" => address.id,
          "label" => address.label,
          "default" => address.default_address?,
          "created_at" => address.created_at
        )
      end
    end

    def records(relation, fields)
      relation.map { |item| record(item, fields) }
    end

    def record(item, fields)
      item.attributes.slice(*fields)
    end

    def record_count(payload)
      payload.is_a?(Array) ? payload.length : 1
    end
  end
end
