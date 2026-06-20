# frozen_string_literal: true

module Community
  class SendSavedSearchDigests < ApplicationService
    def call
      hour = SiteSetting.get("forum.saved_search_digest_hour", "9").to_i
      return ServiceResult.success(skipped: true, reason: :wrong_hour) unless Time.current.hour == hour

      sent = 0
      Community::SavedSearch.notify_daily.includes(:user).find_each do |search|
        result = send_for_search(search)
        sent += 1 if result.success? && result.value[:sent]
      end
      ServiceResult.success(sent: sent)
    end

  private

    def send_for_search(search)
      user = search.user
      return ServiceResult.success(skipped: true) if user.email.blank?

      since = search.last_notified_at || 1.day.ago
      return ServiceResult.success(skipped: true) if search.last_notified_at && search.last_notified_at > 20.hours.ago

      topics = Community::SavedSearchMatcher.new(search).matching_topics(since: since).limit(20).to_a
      return ServiceResult.success(skipped: true) if topics.empty?

      MailDeliveryJob.perform_later(
        "Community::ForumMailer",
        "saved_search_digest",
        "deliver_now",
        args: [ search.id, topics.map(&:id) ]
      )
      notify_in_app!(search, topics)
      Community::DispatchSavedSearchWebhook.call(saved_search: search, topics: topics)
      search.update!(last_notified_at: Time.current)
      ServiceResult.success(sent: true, count: topics.size)
    end

    def notify_in_app!(search, topics)
      return unless search.notify_in_app?

      user = search.user
      return unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.saved_search_match")

      Notification.notify!(
        user: user,
        notification_type: "forum.saved_search_match",
        title: I18n.t("mcweb.forum.saved_search_digest.title", name: search.name),
        body: topics.map(&:title).join(I18n.t("mcweb.commerce.list_separator")).truncate(200),
        metadata: {
          search_id: search.id,
          path: saved_search_notification_path(search)
        }
      )
    end

    def saved_search_notification_path(search)
      params = Community::SavedSearchPresenter.url_params(search).compact
      "#{Mcweb::Paths::APP_PREFIX}/forum/search?#{params.to_query}"
    end
  end
end
