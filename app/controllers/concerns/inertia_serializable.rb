# frozen_string_literal: true

module InertiaSerializable
  extend ActiveSupport::Concern

  private

  def pagy_props(pagy)
    {
      page: pagy.page,
      pages: pagy.pages,
      count: pagy.count,
      from: pagy.from,
      to: pagy.to,
      prev: pagy.prev,
      next: pagy.next
    }
  end

  def inertia_user
    return nil unless current_user

    {
      id: current_user.public_id,
      username: current_user.username,
      email: current_user.email
    }
  end

  def admin_column(key, label, link: false)
    { key: key.to_s, label: label, link: link }
  end

  def admin_row(**attrs)
    attrs.transform_values { |v| v.nil? ? "—" : v.to_s }
  end

  def serialize_section(section)
    {
      id: section.id,
      name: section.name,
      slug: section.slug,
      description: section.description&.truncate(80),
      category_name: section.category&.name,
      url: forum_section_path(section)
    }
  end

  def serialize_topic(topic, read_state: nil)
    unread_count = if read_state
                     read_state.unread_count
                   elsif current_user
                     topic.posts.count
                   else
                     0
                   end

    {
      id: topic.public_id,
      title: topic.title,
      url: forum_topic_path(topic),
      author: topic.user&.username,
      replies_count: topic.replies_count,
      views_count: topic.views_count,
      last_posted_at: topic.last_posted_at ? l(topic.last_posted_at, format: :short) : nil,
      pinned: topic.pinned?,
      locked: topic.locked?,
      featured: topic.featured?,
      unread_count: unread_count,
      has_unread: unread_count.positive?
    }
  end

  def serialize_topic_detail(topic, watching: false, bookmarked: false, can_moderate: false, can_edit: false)
    {
      id: topic.public_id,
      title: topic.title,
      author: topic.user&.username,
      author_url: topic.user ? forum_user_path(topic.user.username) : nil,
      locked: topic.locked?,
      pinned: topic.pinned?,
      hidden: topic.status == "hidden",
      featured: topic.featured?,
      views_count: topic.views_count,
      watching: watching,
      bookmarked: bookmarked,
      can_moderate: can_moderate,
      can_edit: can_edit,
      tags: topic.tags.map { |tag| { name: tag.name, slug: tag.slug, url: forum_tag_path(tag.slug) } },
      tags_string: topic.tags.map(&:name).join(", "),
      section: {
        name: topic.section.name,
        slug: topic.section.slug,
        url: forum_section_path(topic.section)
      }
    }
  end

  def serialize_post(post, current_user: nil, can_moderate: false)
    formatted = Community::FormatPostBody.call(body: post.body)
    body_html = formatted.success? ? formatted.value : ERB::Util.html_escape(post.body)
    reaction_counts = post.reactions.group(:emoji).count
    user_reactions = if current_user
                       post.reactions.where(user: current_user).pluck(:emoji)
                     else
                       []
                     end

    {
      id: post.id,
      floor_number: post.floor_number,
      author: post.user.username,
      author_url: forum_user_path(post.user.username),
      avatar_url: post.user.avatar_url,
      body: post.body,
      body_html: body_html,
      created_at: l(post.created_at, format: :short),
      edited_at: post.edited_at ? l(post.edited_at, format: :short) : nil,
      edit_count: post.edits.count,
      edits_url: post.edits.any? ? edits_forum_post_path(post) : nil,
      quoted_post: serialize_quoted_post(post.quoted_post),
      reaction_counts: reaction_counts,
      user_reactions: user_reactions,
      can_edit: can_edit_post?(post, current_user),
      can_delete: can_delete_post?(post, current_user),
      can_moderate: can_moderate,
      hidden: post.status == "hidden",
      report_url: current_user ? new_forum_report_path(reportable_type: "Community::Post", reportable_id: post.id) : nil,
      update_url: forum_post_path(post)
    }
  end

  def serialize_quoted_post(post)
    return nil unless post

    {
      id: post.id,
      floor_number: post.floor_number,
      author: post.user.username,
      excerpt: post.body.truncate(120)
    }
  end

  def can_edit_post?(post, user)
    Community::EditPost.editable_by?(user, post)
  end

  def can_delete_post?(post, user)
    return false unless user

    user.id == post.user_id || user.permission?("forum.topics.lock")
  end

  def serialize_search_topic(topic)
    {
      id: topic.public_id,
      title: topic.title,
      url: forum_topic_path(topic),
      last_posted_at: topic.last_posted_at ? l(topic.last_posted_at, format: :short) : nil
    }
  end

  def serialize_search_post(post)
    {
      id: post.id,
      body: post.body.truncate(120),
      author: post.user.username,
      topic_title: post.topic.title,
      topic_url: forum_topic_path(post.topic),
      created_at: l(post.created_at, format: :short)
    }
  end

  def serialize_product_list_item(product)
    {
      id: product.public_id,
      name: product.name,
      slug: product.slug,
      category_name: product.category&.name,
      price_label: format_price(product),
      in_stock: product.in_stock?,
      url: store_product_path(product)
    }
  end

  def serialize_product_detail(product, wishlisted: false, reviews: [], average_rating: nil)
    {
      id: product.public_id,
      db_id: product.id,
      name: product.name,
      slug: product.slug,
      description: product.description,
      price_label: format_price(product),
      product_type: product.product_type,
      category_name: product.category&.name,
      in_stock: product.in_stock?,
      purchase_limit: product.purchase_limit,
      wishlisted: wishlisted,
      average_rating: average_rating,
      variants: product.variants.map { |variant| serialize_variant(variant, product) },
      reviews: reviews.map { |review| serialize_review(review) }
    }
  end

  def serialize_review(review)
    {
      id: review.id,
      author: review.user.username,
      rating: review.rating,
      body: review.body,
      created_at: l(review.created_at, format: :short)
    }
  end

  def serialize_variant(variant, product)
    {
      id: variant.id,
      name: variant.name,
      sku: variant.sku,
      price_label: format_money(variant.price_cents, product.currency),
      in_stock: variant.in_stock?
    }
  end

  def serialize_category(category)
    {
      slug: category.slug,
      name: category.name,
      url: store_products_path(category: category.slug)
    }
  end

  def serialize_cart_item(item)
    unit = item.product.currency == "CNY" ? "¥" : "$"
    unit_cents = item.variant&.price_cents || item.product.price_cents
    {
      id: item.id,
      product_name: item.product.name,
      variant_name: item.variant&.name,
      quantity: item.quantity,
      unit_price_label: number_to_currency(unit_cents / 100.0, unit: unit),
      total_label: number_to_currency(item.total_cents / 100.0, unit: unit),
      update_url: store_cart_path
    }
  end

  def serialize_order_list_item(order)
    {
      id: order.public_id,
      order_number: order.order_number,
      status: order.status,
      total_label: format_money(order.total_cents, order.currency),
      created_at: l(order.created_at, format: :short),
      url: store_order_path(order)
    }
  end

  def serialize_order_detail(order)
    {
      id: order.public_id,
      order_number: order.order_number,
      status: order.status,
      total_label: format_money(order.total_cents, order.currency),
      can_pay: order.pending? || order.awaiting_payment?,
      can_cancel: order.pending? || order.awaiting_payment?,
      cancel_url: cancel_store_order_path(order),
      items: order.items.map do |item|
        fulfillment = order.fulfillments.find_by(order_item: item)
        {
          product_name: item.product_name,
          variant_name: item.variant_name,
          quantity: item.quantity,
          total_label: format_money(item.total_cents, order.currency),
          fulfillment_status: fulfillment&.status
        }
      end,
      fulfillments: order.fulfillments.map do |f|
        {
          delivery_id: f.delivery_id,
          status: f.status,
          fulfilled_at: f.fulfilled_at ? l(f.fulfilled_at, format: :short) : nil
        }
      end
    }
  end

  def serialize_article(article)
    {
      id: article.public_id,
      title: article.title,
      slug: article.slug,
      excerpt: article.summary,
      article_type: article.article_type,
      published_at: article.published_at ? l(article.published_at, format: :short) : nil,
      url: "/website/blog/#{article.slug}"
    }
  end

  def serialize_article_detail(article)
    {
      title: article.title,
      summary: article.summary,
      published_at: article.published_at ? l(article.published_at, format: :long) : nil
    }
  end

  def serialize_page_block(block)
    {
      block_type: block.block_type,
      settings: block.settings
    }
  end

  def serialize_session_record(session)
    {
      id: session.id,
      ip_address: session.ip_address,
      user_agent: session.user_agent&.truncate(80),
      last_active_at: session.last_active_at ? l(session.last_active_at, format: :short) : nil,
      current: session.id == current_session&.id
    }
  end

  def serialize_checkout_provider(config)
    { value: config.provider, label: config.provider.humanize }
  end

  def format_price(product)
    format_money(product.price_cents, product.currency)
  end

  def format_money(cents, currency)
    unit = currency == "CNY" ? "¥" : "$"
    number_to_currency(cents / 100.0, unit: unit)
  end

  def number_to_currency(amount, unit:)
    ActionController::Base.helpers.number_to_currency(amount, unit: unit)
  end
end
