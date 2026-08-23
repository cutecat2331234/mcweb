# frozen_string_literal: true

module Website
  class ContentSnapshot
    class << self
      def call(content:)
        case content
        when Website::Page then page_snapshot(content)
        when Website::Article then article_snapshot(content)
        else
          raise ArgumentError, "unsupported website content: #{content.class.name}"
        end
      end

      private

      def page_snapshot(page)
        base_snapshot(page).merge(
          "content_type" => "page",
          "page_type" => page.page_type,
          "website_theme_id" => page.website_theme_id,
          "blocks" => page.blocks.unscope(:order).order(:position, :id).map do |block|
            block.attributes.slice(
              "id", "block_type", "position", "settings", "translations", "visible"
            )
          end
        )
      end

      def article_snapshot(article)
        base_snapshot(article).merge(
          "content_type" => "article",
          "article_type" => article.article_type,
          "summary" => article.summary,
          "body" => article.body
        )
      end

      def base_snapshot(content)
        {
          "public_id" => content.public_id,
          "title" => content.title,
          "slug" => content.slug,
          "status" => content.status,
          "seo" => content.seo.deep_dup,
          "translations" => content.translations.deep_dup,
          "published_at" => content.published_at&.iso8601(6),
          "scheduled_at" => content.scheduled_at&.iso8601(6),
          "author_id" => content.author_id,
          "lock_version" => content.lock_version,
          "discarded_at" => content.discarded_at&.iso8601(6),
          "discarded_by_id" => content.discarded_by_id,
          "discard_reason" => content.discard_reason,
          "purge_at" => content.purge_at&.iso8601(6)
        }
      end
    end
  end
end
