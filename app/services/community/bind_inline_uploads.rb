# frozen_string_literal: true

module Community
  class BindInlineUploads < ApplicationService
    TOKEN_PATTERN = %r{(?:/forum/uploads/|[?&]upload=)(upl_[A-Za-z0-9_-]{20,})}
    LEGACY_BLOB_URL_PATTERN = %r{
      /rails/active_storage/blobs/(?:redirect|proxy)/[^\s)\]]+
      [?&]upload=(upl_[A-Za-z0-9_-]{20,})
    }x

    def initialize(user:, post:, body:)
      @user = user
      @post = post
      @tokens = body.to_s.scan(TOKEN_PATTERN).flatten.uniq
    end

    def call
      return ServiceResult.success(linked: 0) if @tokens.empty?

      linked = 0
      invalid = false
      Community::Upload.transaction do
        uploads = Community::Upload
          .where(user: @user, kind: "inline_image", public_id: @tokens)
          .order(:id)
          .lock
          .to_a

        if uploads.size != @tokens.size
          invalid = true
          raise ActiveRecord::Rollback
        end

        uploads.each do |upload|
          unless bindable?(upload)
            invalid = true
            raise ActiveRecord::Rollback
          end

          next if upload.status_linked? && upload.forum_post_id == @post.id

          upload.update!(
            status: "linked",
            post: @post,
            expires_at: nil,
            cleanup_started_at: nil,
            cleanup_error_code: nil,
            cleanup_error_message: nil
          )
          linked += 1
        end

        canonical_body = canonicalize_legacy_urls(@post.body.to_s)
        @post.update!(body: canonical_body) if canonical_body != @post.body
      end

      if invalid
        return ServiceResult.failure(
          error: "inline_upload_expired",
          code: "inline_upload_expired"
        )
      end

      ServiceResult.success(linked: linked)
    end

    private

    def bindable?(upload)
      return false unless upload.scan_clean?
      return true if upload.status_linked? && upload.forum_post_id == @post.id
      return false unless upload.status_stored?
      return false if upload.forum_post_id.present?
      return false if upload.expires_at&.<=(Time.current)

      true
    end

    def canonicalize_legacy_urls(body)
      body.gsub(LEGACY_BLOB_URL_PATTERN) do
        Rails.application.routes.url_helpers.forum_upload_path(Regexp.last_match(1))
      end
    end
  end
end
