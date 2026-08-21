# frozen_string_literal: true

module Commerce
  class UpdateReview < ApplicationService
    def initialize(
      user:,
      review:,
      rating:,
      expected_version: nil,
      body: nil,
      retained_photo_ids: nil,
      photo_selection_present: false,
      photos: nil
    )
      @user = user
      @review = review
      @rating = rating.to_i
      @body = body&.strip
      @expected_version = Integer(expected_version, exception: false)
      @expected_version = nil if @expected_version&.negative?
      @photo_selection_present = ActiveModel::Type::Boolean.new.cast(photo_selection_present)
      retained_values = Array(retained_photo_ids).reject(&:blank?) if @photo_selection_present
      parsed_retained_ids = retained_values&.map { |value| Integer(value, exception: false) }
      @retained_photo_ids_invalid = parsed_retained_ids&.any?(&:nil?) || false
      @retained_photo_ids = parsed_retained_ids&.compact&.uniq
      @photos = Commerce::ReviewPhotoValidator.files(photos)
    end

    def call
      return service_failure(:review_update_unauthorized) unless @review.user_id == @user.id
      return service_failure(:review_revision_required) unless @expected_version
      return service_failure(:review_rating_invalid) unless (1..5).cover?(@rating)
      return service_failure(:review_body_too_long) if @body.to_s.length > 5_000
      return service_failure(:review_photo_selection_invalid) if @retained_photo_ids_invalid

      updated_review = nil
      failure_error = nil
      stale_blobs = []

      Commerce::Review.transaction do
        review = Commerce::Review.lock.find(@review.id)
        unless review.user_id == @user.id
          failure_error = :review_update_unauthorized
          raise ActiveRecord::Rollback
        end
        unless review.published?
          failure_error = review.hidden? ? :review_hidden_by_moderator : :review_not_editable
          raise ActiveRecord::Rollback
        end
        unless review.lock_version == @expected_version
          failure_error = :review_update_conflict
          raise ActiveRecord::Rollback
        end

        attachments = review.photos.attachments.includes(:blob).to_a
        retained = if @photo_selection_present
          known_ids = attachments.map(&:id)
          unless (@retained_photo_ids - known_ids).empty?
            failure_error = :review_photo_selection_invalid
            raise ActiveRecord::Rollback
          end
          attachments.select { |attachment| @retained_photo_ids.include?(attachment.id) }
        else
          attachments
        end

        if (photo_error = Commerce::ReviewPhotoValidator.validate(@photos, retained_count: retained.length))
          failure_error = photo_error
          raise ActiveRecord::Rollback
        end

        before_state = review.attributes.slice("rating", "status").merge(
          Commerce::AuditContentSnapshot.fields("body", review.body)
        ).merge("photo_ids" => attachments.map(&:id))
        removed_attachments = attachments - retained
        stale_blobs = removed_attachments.map(&:blob)
        removed_attachments.each(&:delete)
        review.update!(rating: @rating, body: @body)
        @photos.each { |photo| review.photos.attach(photo) }
        review.reload

        Administration::AuditLogger.call(
          actor: @user,
          action: "commerce.review_updated",
          resource: review,
          metadata: {
            product_public_id: review.product.public_id,
            changed_fields: changed_fields(before_state, review)
          },
          before_state: before_state,
          after_state: review.attributes.slice("rating", "status").merge(
            Commerce::AuditContentSnapshot.fields("body", review.body)
          ).merge("photo_ids" => review.photos.attachments.pluck(:id))
        )
        updated_review = review
      end

      return service_failure(failure_error) if failure_error

      purge_after_commit(stale_blobs)
      ServiceResult.success(updated_review)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def service_failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def changed_fields(before_state, review)
      fields = []
      fields << "rating" if before_state["rating"] != review.rating
      fields << "body" if before_state["body_sha256"] != Commerce::AuditContentSnapshot.fields("body", review.body)["body_sha256"]
      fields << "photos" if before_state["photo_ids"] != review.photos.attachments.pluck(:id)
      fields
    end

    def purge_after_commit(blobs)
      return if blobs.empty?

      ActiveRecord.after_all_transactions_commit { blobs.each(&:purge_later) }
    end
  end
end
