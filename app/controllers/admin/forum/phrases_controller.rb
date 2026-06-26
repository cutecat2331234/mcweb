# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style "phrases": DB-backed translation overrides.
    class PhrasesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_phrase, only: %i[edit update destroy]

      LOCALES = %w[en zh-CN].freeze

      def index
        scope = ::Community::PhraseOverride.ordered
        query = params[:q].to_s.strip
        if query.present?
          like = "%#{::ActiveRecord::Base.sanitize_sql_like(query)}%"
          scope = scope.where("key ILIKE ? OR value ILIKE ?", like, like)
        end

        @pagy, phrases = pagy(:offset, scope, limit: 30)

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("phrases.title"),
          subtitle: forum_t("phrases.description"),
          columns: [
            admin_column(:key, forum_t("phrases.col_key"), link: true),
            admin_column(:locale, forum_t("phrases.col_locale")),
            admin_column(:value, forum_t("phrases.col_value"))
          ],
          rows: phrases.map do |phrase|
            admin_row(
              key: phrase.key,
              locale: phrase.locale,
              value: phrase.value.to_s.truncate(60),
              url: edit_admin_forum_phrase_path(phrase)
            )
          end,
          pagination: pagy_props(@pagy),
          actions: [ { label: forum_t("phrases.action_new"), href: new_admin_forum_phrase_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/Phrases/Form", props: form_props(::Community::PhraseOverride.new(locale: "en"))
      end

      def create
        phrase = ::Community::PhraseOverride.new(phrase_params)
        if phrase.save
          redirect_to admin_forum_phrases_path, notice: t("mcweb.flash.phrase_saved")
        else
          render inertia: "Admin/Forum/Phrases/Form", props: form_props(phrase), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/Phrases/Form", props: form_props(@phrase, editing: true)
      end

      def update
        if @phrase.update(phrase_params)
          redirect_to admin_forum_phrases_path, notice: t("mcweb.flash.phrase_saved")
        else
          render inertia: "Admin/Forum/Phrases/Form", props: form_props(@phrase, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @phrase.destroy!
        redirect_to admin_forum_phrases_path, notice: t("mcweb.flash.phrase_deleted")
      end

      private

      def set_phrase
        @phrase = ::Community::PhraseOverride.find(params[:id])
      end

      def phrase_params
        params.require(:phrase).permit(:locale, :key, :value)
      end

      def form_props(phrase, editing: false)
        {
          title: editing ? forum_t("phrases.form_edit") : forum_t("phrases.form_new"),
          phrase: {
            locale: phrase.locale || "en",
            key: phrase.key || "",
            value: phrase.value || ""
          },
          localeOptions: LOCALES.map { |l| { value: l, label: l } },
          submitUrl: editing ? admin_forum_phrase_path(phrase) : admin_forum_phrases_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_phrases_path,
          deleteUrl: editing ? admin_forum_phrase_path(phrase) : nil
        }
      end
    end
  end
end
