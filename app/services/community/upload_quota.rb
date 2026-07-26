# frozen_string_literal: true

module Community
  # Durable accepted-upload quotas. Administration::AbuseRateLimit remains the
  # request/burst boundary (account + IP) and runs before any file is inspected.
  # This service accounts only uploads that passed content inspection, enforcing
  # retained bytes/count plus accepted-upload frequency at site, group, and
  # account scopes.
  class UploadQuota < ApplicationService
    ADVISORY_LOCK_ID = 6_421_697_132_025_072_601
    ONE_HOUR = 1.hour
    MAX_BYTES = 10.petabytes
    MAX_COUNT = 100_000_000

    DEFAULTS = {
      site: {
        bytes: 100.gigabytes,
        count: 100_000,
        hourly_count: 5_000
      },
      group: {
        bytes: 20.gigabytes,
        count: 20_000,
        hourly_count: 1_000
      },
      account: {
        bytes: 512.megabytes,
        count: 1_000,
        hourly_count: 120
      }
    }.freeze

    def initialize(user:, kind:, byte_size:)
      @user = user
      @kind = kind.to_s
      @byte_size = Integer(byte_size, exception: false)
    end

    def self.site_usage(at: Time.current)
      retained = Community::Upload.counted_toward_quota

      {
        bytes: {
          used: retained.sum(:byte_size),
          limit: configured_site_limit(:bytes)
        },
        count: {
          used: retained.count,
          limit: configured_site_limit(:count)
        },
        hourly_count: {
          used: Community::Upload.where("created_at >= ?", at - ONE_HOUR).count,
          limit: configured_site_limit(:hourly_count)
        }
      }
    end

    def self.configured_site_limit(metric)
      default = DEFAULTS.fetch(:site).fetch(metric)
      maximum = metric == :bytes ? MAX_BYTES : MAX_COUNT
      parsed = Integer(
        SiteSetting.get("forum.upload_quota.site.#{metric}", default.to_s),
        exception: false
      )
      parsed&.between?(0, maximum) ? parsed : default
    end
    private_class_method :configured_site_limit

    def call
      return ServiceResult.failure(error: "upload_quota_invalid") unless valid_input?

      upload = nil
      rejection = nil
      Community::Upload.transaction(requires_new: true) do
        acquire_quota_lock!

        unless Mcweb::DeveloperMode.allow?(:skip_attachment_quota)
          quota_scopes.each do |scope|
            rejection = exceeded_limit(scope)
            break if rejection
          end
        end

        if rejection
          raise ActiveRecord::Rollback
        end

        upload = Community::Upload.create!(
          user: @user,
          public_id: Community::Upload.generate_public_id,
          kind: @kind,
          status: "reserved",
          byte_size: @byte_size,
          expires_at: 1.hour.from_now
        )
      end

      if rejection
        instrument_rejection(rejection)
        return ServiceResult.failure(
          error: "upload_quota_exceeded",
          code: "upload_quota_exceeded",
          value: rejection
        )
      end

      instrument("community.upload.reserved", upload_id: upload.id, byte_size: @byte_size)
      ServiceResult.success(upload)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def valid_input?
      @user&.persisted? &&
        Community::Upload::KINDS.include?(@kind) &&
        @byte_size&.positive?
    end

    def acquire_quota_lock!
      ApplicationRecord.connection.select_value(
        "SELECT pg_advisory_xact_lock(#{ADVISORY_LOCK_ID})::text"
      )
    end

    def quota_scopes
      scopes = [
        {
          type: :site,
          id: nil,
          relation: Community::Upload.all
        }
      ]
      @user.user_groups.order(:id).each do |group|
        user_ids = Community::GroupMembership
          .where(community_user_group_id: group.id)
          .select(:user_id)
        scopes << {
          type: :group,
          id: group.id,
          relation: Community::Upload.where(user_id: user_ids)
        }
      end
      scopes << {
        type: :account,
        id: @user.id,
        relation: Community::Upload.where(user_id: @user.id)
      }
      scopes
    end

    def exceeded_limit(scope)
      retained = scope.fetch(:relation).counted_toward_quota
      limits_for(scope).each do |metric, limit|
        next if limit.zero?

        used, requested =
          case metric
          when :bytes
            [ retained.sum(:byte_size), @byte_size ]
          when :count
            [ retained.count, 1 ]
          when :hourly_count
            [ scope.fetch(:relation).where("created_at >= ?", ONE_HOUR.ago).count, 1 ]
          end
        next if used + requested <= limit

        return {
          scope: scope.fetch(:type).to_s,
          scope_id: scope[:id],
          metric: metric.to_s,
          limit: limit,
          used: used,
          requested: requested
        }
      end
      nil
    end

    def limits_for(scope)
      type = scope.fetch(:type)
      DEFAULTS.fetch(type).to_h do |metric, default|
        key =
          if type == :group
            "forum.upload_quota.group.#{scope.fetch(:id)}.#{metric}"
          else
            "forum.upload_quota.#{type}.#{metric}"
          end
        generic_group_key = "forum.upload_quota.group.#{metric}"
        fallback =
          if type == :group
            configured_integer(generic_group_key, default, maximum_for(metric))
          else
            default
          end

        [ metric, configured_integer(key, fallback, maximum_for(metric)) ]
      end
    end

    def configured_integer(key, default, maximum)
      parsed = Integer(SiteSetting.get(key, default.to_s), exception: false)
      return default unless parsed&.between?(0, maximum)

      parsed
    end

    def maximum_for(metric)
      metric == :bytes ? MAX_BYTES : MAX_COUNT
    end

    def instrument_rejection(rejection)
      instrument(
        "community.upload.quota_rejected",
        rejection.merge(byte_size: @byte_size)
      )
      Rails.logger.warn(
        "[Community::UploadQuota] rejected user_id=#{@user.id} " \
        "scope=#{rejection[:scope]} scope_id=#{rejection[:scope_id]} " \
        "metric=#{rejection[:metric]} limit=#{rejection[:limit]} " \
        "used=#{rejection[:used]} requested=#{rejection[:requested]}"
      )
    end

    def instrument(name, payload)
      ActiveSupport::Notifications.instrument(
        name,
        payload.merge(user_id: @user.id, kind: @kind)
      )
    end
  end
end
