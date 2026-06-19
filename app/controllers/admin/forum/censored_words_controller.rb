# frozen_string_literal: true

module Admin
  module Forum
    class CensoredWordsController < BaseController
      before_action -> { require_permission("forum.topics.lock") }

      def index
        words = Community::CensoredWord.ordered

        render inertia: "Admin/Forum/CensoredWords/Index", props: {
          words: words.map { |w| { id: w.id, word: w.word, replacement: w.replacement, destroy_url: admin_forum_censored_word_path(w) } },
          createUrl: admin_forum_censored_words_path
        }
      end

      def create
        word = Community::CensoredWord.new(censored_word_params)
        if word.save
          Rails.cache.delete("forum/censored_words")
          redirect_to admin_forum_censored_words_path, notice: t("mcweb.flash.censored_word_added")
        else
          redirect_to admin_forum_censored_words_path, alert: word.errors.full_messages.to_sentence
        end
      end

      def destroy
        Community::CensoredWord.find(params[:id]).destroy!
        Rails.cache.delete("forum/censored_words")
        redirect_to admin_forum_censored_words_path, notice: t("mcweb.flash.censored_word_deleted")
      end

      private

      def censored_word_params
        params.require(:censored_word).permit(:word, :replacement)
      end
    end
  end
end
