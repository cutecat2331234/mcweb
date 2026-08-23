# frozen_string_literal: true

module Community
  module ModerationWorkbench
    class CaseDetail < ApplicationService
      def initialize(actor:, moderation_case:)
        @actor = actor
        @moderation_case = moderation_case
        @policy = Policy.new(actor)
      end

      def call
        return ServiceResult.failure(error: "moderation_case_forbidden") unless @policy.visible?(@moderation_case)

        base = Queue.new(actor: @actor).serialize(@moderation_case)
        ServiceResult.success(
          base.merge(
            metadata: @moderation_case.metadata,
            evidence: evidence,
            notes: notes,
            assignable_staff: @policy.assignable_staff(@moderation_case).map do |user|
              { id: user.id, value: user.id, username: user.username, name: user.username }
            end
          )
        )
      rescue ActiveRecord::RecordNotFound
        ServiceResult.failure(error: "moderation_case_stale")
      end

      private

      def evidence
        return restricted_evidence unless @policy.evidence_visible?(@moderation_case)

        source = evidence_source
        case source
        when Community::Post then post_evidence(source)
        when Community::Report then report_evidence(source)
        when Community::Upload then upload_evidence(source)
        when Community::UserWarning then warning_evidence(source)
        when Community::Mute then mute_evidence(source)
        when User then ban_evidence(source)
        else restricted_evidence
        end
      end

      def post_evidence(post)
        unless Community::ForumAccess.post_visible?(post: post, user: @actor)
          return restricted_evidence
        end

        body, cropped = crop_text(post.body)
        {
          restricted: false,
          cropped: cropped,
          type: "post",
          body: body,
          author: post.user.username,
          topic_title: post.topic.title,
          floor_number: post.floor_number,
          status: post.status,
          submitted_at: post.created_at.iso8601,
          attachments: post_attachments(post)
        }
      end

      def report_evidence(report)
        target = report.reportable
        reason, reason_cropped = crop_text(report.reason)
        target_evidence = report_target_evidence(target)
        {
          restricted: false,
          cropped: reason_cropped || target_evidence[:cropped],
          type: "report",
          reason: reason,
          reason_code: report.reason_code,
          reporter: report.reporter.username,
          submitted_at: report.created_at.iso8601,
          target: target_evidence,
          attachments: report_attachments(report)
        }
      end

      def report_attachments(report)
        report.evidence_links
          .includes(attachment: :upload_record)
          .order(:created_at, :id)
          .filter_map do |link|
            attachment = link.attachment
            upload = attachment.upload_record
            next unless attachment.state_available? && upload&.scan_clean?

            {
              public_id: attachment.public_id,
              filename: attachment.filename,
              byte_size: attachment.byte_size,
              download_url: Rails.application.routes.url_helpers.secure_evidence_attachment_path(attachment)
            }
          end
      end

      def upload_evidence(upload)
        attachment = upload.post_attachment
        blob = upload.blob
        {
          restricted: false,
          type: "attachment",
          public_id: upload.public_id,
          filename: attachment&.filename || blob&.filename&.to_s,
          byte_size: upload.byte_size,
          content_type: blob&.content_type,
          scan_status: upload.scan_status,
          scan_result_code: upload.scan_result_code,
          scanner: upload.scanner,
          quarantined_at: upload.quarantined_at&.iso8601,
          manual_review_status: upload.manual_review_status,
          owner: upload.user.username
        }.compact
      end

      def warning_evidence(warning)
        reason, cropped = crop_optional_text(warning.reason)
        {
          restricted: false,
          cropped: cropped,
          type: "warning",
          user: warning.user.username,
          issuer: warning.issuer.username,
          reason: reason,
          points: warning.points,
          expires_at: warning.expires_at&.iso8601
        }.compact
      end

      def mute_evidence(mute)
        reason, cropped = crop_optional_text(mute.reason)
        {
          restricted: false,
          cropped: cropped,
          type: "mute",
          user: mute.user.username,
          created_by: mute.created_by.username,
          section: mute.section&.name,
          reason: reason,
          expires_at: mute.expires_at&.iso8601
        }.compact
      end

      def ban_evidence(user)
        reason, cropped = crop_optional_text(user.ban_reason)
        {
          restricted: false,
          cropped: cropped,
          type: "ban",
          user: user.username,
          reason: reason,
          banned_at: user.banned_at&.iso8601,
          expires_at: user.ban_expires_at&.iso8601
        }.compact
      end

      def report_target_evidence(target)
        return { type: "missing", restricted: true, cropped: true } unless target

        case target
        when Community::Post
          return { type: "post", restricted: true } unless Community::ForumAccess.post_visible?(
            post: target,
            user: @actor
          )

          body, cropped = crop_text(target.body)
          {
            type: "post",
            restricted: false,
            cropped: cropped,
            body: body,
            author: target.user.username,
            topic_title: target.topic.title,
            floor_number: target.floor_number
          }
        when Community::Topic
          opening_post = target.posts.order(:floor_number).first
          readable = opening_post && Community::ForumAccess.post_visible?(
            post: opening_post,
            user: @actor
          )
          body, cropped = crop_text(opening_post&.body)
          {
            type: "topic",
            restricted: !readable,
            cropped: readable && cropped,
            title: target.title,
            body: readable ? body : nil,
            author: readable ? target.user.username : nil
          }.compact
        when User
          { type: "user", restricted: false, username: target.username }
        else
          { type: target.class.base_class.name, restricted: true }
        end
      end

      def post_attachments(post)
        return { restricted: true, count: post.attachments.size } unless @policy.attachment_reader?

        post.attachments.map do |attachment|
          {
            id: attachment.id,
            filename: attachment.filename,
            byte_size: attachment.byte_size,
            scan_status: attachment.upload_record&.scan_status
          }.compact
        end
      end

      def restricted_evidence
        {
          restricted: true,
          cropped: true,
          reason: "additional_moderation_evidence_permission_required"
        }
      end

      def evidence_source
        if @moderation_case.source_type == "Community::Post"
          Community::Post.with_discarded.find(@moderation_case.source_id)
        else
          @moderation_case.source
        end
      end

      def crop_text(value, limit: 12_000)
        text = value.to_s
        [ text.first(limit), text.length > limit ]
      end

      def crop_optional_text(value, limit: 12_000)
        return [ nil, false ] if value.nil?

        crop_text(value, limit: limit)
      end

      def notes
        @moderation_case.notes.includes(:author).order(created_at: :asc).map do |note|
          {
            id: note.id,
            body: note.body,
            author: {
              id: note.author.id,
              username: note.author.username,
              name: note.author.username
            },
            created_at: note.created_at.iso8601
          }
        end
      end
    end
  end
end
