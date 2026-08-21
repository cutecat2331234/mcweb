# frozen_string_literal: true

module Community
  class EditProfileWallItem < ApplicationService
    MAX_LENGTHS = {
      "Community::ProfilePost" => 5_000,
      "Community::ProfilePostComment" => 3_000
    }.freeze

    def initialize(author:, item:, body:, expected_revision:, request_id: nil)
      @author = author
      @item = item
      @body = body
      @expected_revision = Integer(expected_revision, exception: false)
      @request_id = request_id
    end

    def call
      max_length = MAX_LENGTHS[@item&.class&.name]
      return failure("profile_post_unavailable") unless max_length
      return failure("profile_post_edit_author_only") unless @author&.id == @item.user_id
      return failure("profile_post_unavailable") unless Community::ProfileWallPolicy.enabled?
      return failure("profile_post_unavailable") if @item.deleted_at.present? || !@item.published?
      if @item.is_a?(Community::ProfilePostComment) && !profile_post_available?
        return failure("profile_post_unavailable")
      end
      return failure("profile_post_revision_required") unless @expected_revision&.positive?

      prepared = Community::PrepareProfileWallBody.call(
        author: @author,
        body: @body,
        max_length: max_length
      )
      return prepared if prepared.failure?

      result = nil
      @item.class.transaction do
        @item.lock!
        if @item.revision != @expected_revision
          result = failure("profile_post_revision_conflict")
          raise ActiveRecord::Rollback
        end
        if @item.deleted_at.present? || !@item.published?
          result = failure("profile_post_unavailable")
          raise ActiveRecord::Rollback
        end
        if @item.is_a?(Community::ProfilePostComment) && !profile_post_available?(lock: true)
          result = failure("profile_post_unavailable")
          raise ActiveRecord::Rollback
        end

        previous_revision = @item.revision
        previous_digest = Digest::SHA256.hexdigest(@item.body)
        @item.update!(
          body: prepared.value,
          edited_at: Time.current,
          revision: @item.revision + 1
        )
        current_digest = Digest::SHA256.hexdigest(@item.body)
        audit_result = Administration::AuditLogger.call(
          actor: @author,
          action: "community.profile_wall_item_updated",
          resource: @item,
          request_id: @request_id,
          metadata: {
            changed_fields: [ "body" ],
            item_type: @item.class.base_class.name,
            previous_revision: previous_revision,
            revision: @item.revision,
            body_length: @item.body.length,
            body_digest: current_digest
          },
          before_state: {
            revision: previous_revision,
            body_digest: previous_digest
          },
          after_state: {
            revision: @item.revision,
            body_digest: current_digest
          }
        )
        if audit_result.failure?
          result = audit_result
          raise ActiveRecord::Rollback
        end
        result = ServiceResult.success(@item)
      end
      result
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def profile_post_available?(lock: false)
      scope = Community::ProfilePost.where(id: @item.profile_post_id, status: "published")
      scope = scope.lock if lock
      scope.first.present?
    end
  end
end
