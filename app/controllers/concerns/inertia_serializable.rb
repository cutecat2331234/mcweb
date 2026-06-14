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

  def serialize_section(section, include_children: true, unread_map: {})
    data = {
      id: section.id,
      name: section.name,
      slug: section.slug,
      description: section.description&.truncate(80),
      category_name: section.category&.name,
      topics_count: section.topics.where(status: :published).count,
      unread_count: unread_map[section.id].to_i,
      url: forum_section_path(section)
    }

    if include_children && section.children.any?
      data[:children] = section.children.ordered.map { |child| serialize_section(child, include_children: false, unread_map: unread_map) }
    end

    data
  end

  def serialize_topic(topic, read_state: nil)
    unread_count = if read_state
                     read_state.unread_count
                   elsif current_user
                     0
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
      prefix: topic.prefix,
      locked: topic.locked?,
      featured: topic.featured?,
      solved: topic.solved_post_id.present?,
      unread_count: unread_count,
      has_unread: unread_count.positive?
    }
  end

  def serialize_topic_detail(topic, watching: false, bookmarked: false, can_moderate: false, can_move: false, can_edit: false)
    {
      id: topic.public_id,
      title: topic.title,
      author: topic.user ? forum_author_name(topic.user) : nil,
      author_username: topic.user&.username,
      author_url: topic.user ? forum_user_path(topic.user.username) : nil,
      locked: topic.locked?,
      pinned: topic.pinned?,
      pinned_until: topic.pinned_until ? l(topic.pinned_until, format: :short) : nil,
      bumped_at: topic.bumped_at ? l(topic.bumped_at, format: :short) : nil,
      hidden: topic.status == "hidden",
      featured: topic.featured?,
      wiki: topic.wiki?,
      slow_mode_seconds: topic.slow_mode_seconds,
      auto_close_at: topic.auto_close_at ? l(topic.auto_close_at, format: :short) : nil,
      solved_post_id: topic.solved_post_id,
      views_count: topic.views_count,
      watching: watching,
      bookmarked: bookmarked,
      can_moderate: can_moderate,
      can_move: can_move,
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

  def serialize_post(post, current_user: nil, can_moderate: false, solved_post_id: nil, post_bookmark: nil)
    formatted = Community::FormatPostBody.call(body: post.body)
    body_html = formatted.success? ? formatted.value : ERB::Util.html_escape(post.body)
    reaction_counts = post.reactions.group(:emoji).count
    reaction_users = post.reactions.includes(:user).group_by(&:emoji).transform_values do |reactions|
      reactions.map { |reaction| reaction.user.username }.uniq.first(15)
    end
    user_reactions = if current_user
                       post.reactions.where(user: current_user).pluck(:emoji)
                     else
                       []
                     end
    bookmarked = post_bookmark.present? || (current_user && Community::Bookmark.exists?(user: current_user, post: post))
    bookmark_meta = if post_bookmark
                      {
                        id: post_bookmark.id,
                        update_url: forum_bookmark_path(post_bookmark),
                        note: post_bookmark.note,
                        remind_at_input: post_bookmark.remind_at&.strftime("%Y-%m-%dT%H:%M")
                      }
                    end

    signature_html = nil
    if post.user.forum_signature.present?
      formatted_sig = Community::FormatPostBody.call(body: post.user.forum_signature)
      signature_html = formatted_sig.success? ? formatted_sig.value : ERB::Util.html_escape(post.user.forum_signature)
    end

    {
      id: post.id,
      floor_number: post.floor_number,
      parent_post_id: post.parent_post_id,
      depth: post_depth(post),
      is_solved: solved_post_id == post.id,
      author: forum_author_name(post.user),
      author_username: post.user.username,
      author_url: forum_user_path(post.user.username),
      avatar_url: post.user.avatar_url,
      body: post.body,
      body_html: body_html,
      signature_html: signature_html,
      created_at: l(post.created_at, format: :short),
      edited_at: post.edited_at ? l(post.edited_at, format: :short) : nil,
      edit_count: post.edits.count,
      edits_url: post.edits.any? ? edits_forum_post_path(post) : nil,
      quoted_post: serialize_quoted_post(post.quoted_post),
      reaction_counts: reaction_counts,
      reaction_users: reaction_users,
      reactions_total: reaction_counts.values.sum,
      user_reactions: user_reactions,
      can_edit: can_edit_post?(post, current_user),
      can_delete: can_delete_post?(post, current_user),
      can_moderate: can_moderate,
      bookmarked: bookmarked,
      bookmark_url: current_user ? bookmark_forum_post_path(post) : nil,
      bookmark: bookmark_meta,
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

  def post_depth(post)
    depth = 0
    current = post.parent_post
    while current && depth < 10
      depth += 1
      current = current.parent_post
    end
    depth
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
      topic_url: "#{forum_topic_path(post.topic)}#post-#{post.id}",
      created_at: l(post.created_at, format: :short)
    }
  end

  def serialize_activity_post(post)
    formatted = Community::FormatPostBody.call(body: post.body)
    {
      id: post.id,
      floor_number: post.floor_number,
      author: forum_author_name(post.user),
      author_url: forum_user_path(post.user.username),
      body_excerpt: post.body.truncate(200),
      body_html: formatted.success? ? formatted.value : ERB::Util.html_escape(post.body),
      topic_title: post.topic.title,
      topic_url: forum_topic_path(post.topic),
      section_name: post.topic.section.name,
      created_at: l(post.created_at, format: :short)
    }
  end

  def serialize_product_list_item(product)
    avg = product.reviews.published.average(:rating)&.round(1)
    {
      id: product.public_id,
      name: product.name,
      slug: product.slug,
      category_name: product.category&.name,
      price_label: format_price(product),
      in_stock: product.in_stock?,
      low_stock: product.low_stock?,
      average_rating: avg,
      image_url: product_image_url(product),
      url: store_product_path(product)
    }
  end

  def product_image_url(product)
    if product.cover_image.attached?
      rails_blob_path(product.cover_image, only_path: true)
    else
      product.image_url
    end
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
      low_stock: product.low_stock?,
      purchase_limit: product.purchase_limit,
      image_url: product_image_url(product),
      gallery_urls: product.gallery_urls || [],
      version: product.version,
      changelog: product.changelog,
      view_count: product.view_count,
      wishlisted: wishlisted,
      average_rating: average_rating,
      variants: product.variants.map { |variant| serialize_variant(variant, product) },
      reviews: reviews.map { |review| serialize_review(review, current_user: current_user) }
    }
  end

  def serialize_review(review, current_user: nil)
    helpful = current_user && Commerce::ReviewHelpfulVote.exists?(user: current_user, review: review)
    verified = Commerce::CreateReview.purchased?(user: review.user, product: review.product)
    {
      id: review.id,
      author: review.user.username,
      rating: review.rating,
      body: review.body,
      created_at: l(review.created_at, format: :short),
      helpful_count: review.helpful_votes.count,
      helpful: helpful,
      helpful_url: current_user && current_user.id != review.user_id ? helpful_store_product_review_path(review.product.public_id, review.id) : nil,
      verified_purchaser: verified,
      photo_urls: review.photos.map { |photo| rails_blob_path(photo, only_path: true) }
    }
  end

  def serialize_poll(poll)
    user_votes = poll.votes.where(user: current_user)
    user_vote_indices = user_votes.pluck(:option_index)
    show_results = !poll.hide_results_until_vote || user_votes.exists? || !poll.open?
    can_close = logged_in? && (current_user.id == poll.topic.user_id || current_user.permission?("forum.topics.lock"))
    {
      id: poll.id,
      question: poll.question,
      open: poll.open?,
      multiple_choice: poll.multiple_choice?,
      max_choices: poll.max_choices,
      hide_results_until_vote: poll.hide_results_until_vote,
      show_results: show_results,
      options: poll.options.each_with_index.map { |label, index| { label: label, index: index } },
      results: show_results ? poll.results : [],
      total_votes: show_results ? poll.total_votes : nil,
      user_vote_index: user_vote_indices.first,
      user_vote_indices: user_vote_indices,
      vote_url: forum_poll_vote_path(poll),
      close_url: can_close && poll.open? ? close_forum_poll_path(poll) : nil,
      closes_at: poll.closes_at ? l(poll.closes_at, format: :short) : nil
    }
  end

  def serialize_variant(variant, product)
    {
      id: variant.id,
      name: variant.name,
      sku: variant.sku,
      price_label: format_money(variant.price_cents, product.currency),
      in_stock: variant.in_stock?,
      low_stock: variant.low_stock?
    }
  end

  def serialize_category(category, **query)
    {
      slug: category.slug,
      name: category.name,
      url: store_products_path(query.merge(category: category.slug).compact)
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
      product_url: store_product_path(item.product),
      update_url: store_cart_path
    }
  end

  ORDER_STATUS_LABELS = {
    "pending" => "待支付",
    "awaiting_payment" => "等待支付",
    "paid" => "已支付",
    "processing" => "处理中",
    "fulfilling" => "发货中",
    "fulfilled" => "已发货",
    "completed" => "已完成",
    "cancelled" => "已取消",
    "refunded" => "已退款",
    "failed" => "失败"
  }.freeze

  REFUND_STATUS_LABELS = {
    "pending" => "待审核",
    "approved" => "已批准",
    "rejected" => "已拒绝",
    "completed" => "已完成"
  }.freeze

  FULFILLMENT_STATUS_LABELS = {
    "pending" => "待处理",
    "processing" => "处理中",
    "fulfilled" => "已完成",
    "failed" => "失败"
  }.freeze

  ORDER_EVENT_LABELS = {
    "created" => "订单创建",
    "payment_submitted" => "提交支付",
    "submit_payment" => "提交支付",
    "payment_confirmed" => "支付成功",
    "paid" => "支付成功",
    "mark_paid" => "支付成功",
    "cancel" => "订单取消",
    "cancelled" => "订单取消",
    "refund_requested" => "退款申请",
    "refund_processed" => "退款完成",
    "refund_rejected" => "退款拒绝",
    "refunded" => "已退款",
    "fulfilled" => "发货完成"
  }.freeze

  def serialize_order_list_item(order)
    {
      id: order.public_id,
      order_number: order.order_number,
      status: order.status,
      status_label: order_status_label(order.status),
      total_label: format_money(order.total_cents, order.currency),
      created_at: l(order.created_at, format: :short),
      url: store_order_path(order),
      can_reorder: order.items.any?,
      reorder_url: reorder_store_order_path(order)
    }
  end

  def serialize_order_detail(order)
    providers = Payments::ProviderConfig.enabled_providers.map { |config| serialize_checkout_provider(config) }
    {
      id: order.public_id,
      order_number: order.order_number,
      status: order.status,
      status_label: order_status_label(order.status),
      notes: order.notes,
      subtotal_label: format_money(order.subtotal_cents, order.currency),
      discount_label: order.discount_cents.positive? ? format_money(order.discount_cents, order.currency) : nil,
      coupon_code: order.coupon&.code,
      total_label: format_money(order.total_cents, order.currency),
      receipt_url: receipt_store_order_path(order),
      receipt_pdf_url: receipt_pdf_store_order_path(order),
      can_pay: order.pending? || order.awaiting_payment?,
      can_cancel: order.pending? || order.awaiting_payment?,
      can_request_refund: refundable_order?(order),
      refund_pending: order.refunds.pending.exists?,
      can_download_receipt: %w[paid processing fulfilling fulfilled completed refunded].include?(order.status),
      refund_url: refund_store_order_path(order),
      refunds: order.refunds.order(created_at: :desc).map do |refund|
        {
          amount_label: format_money(refund.amount_cents, order.currency),
          status: refund.status,
          status_label: REFUND_STATUS_LABELS[refund.status] || refund.status,
          reason: refund.reason,
          created_at: l(refund.created_at, format: :short),
          customer_requested: refund.requested_by_customer?
        }
      end,
      events: order.events.chronological.map do |event|
        {
          event_type: event.event_type,
          label: ORDER_EVENT_LABELS[event.event_type] || event.event_type.humanize,
          created_at: l(event.created_at, format: :short)
        }
      end,
      cancel_url: cancel_store_order_path(order),
      reorder_url: reorder_store_order_path(order),
      can_reorder: order.items.any?,
      items: order.items.map do |item|
        fulfillment = order.fulfillments.find_by(order_item: item)
        snapshot = item.fulfillment_snapshot || {}
        config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
        download_url = signed_download_url_for(item)
        refresh_download_url = download_url.present? ? refresh_download_store_order_path(order, order_item_id: item.id) : nil
        {
          id: item.id,
          product_name: item.product_name,
          variant_name: item.variant_name,
          quantity: item.quantity,
          total_label: format_money(item.total_cents, order.currency),
          fulfillment_status: fulfillment&.status,
          fulfillment_status_label: fulfillment_status_label(fulfillment&.status),
          download_url: download_url,
          refresh_download_url: refresh_download_url
        }
      end,
      downloads: order.items.filter_map do |item|
        url = signed_download_url_for(item)
        next if url.blank?

        { product_name: item.product_name, url: url }
      end,
      fulfillments: order.fulfillments.map do |f|
        {
          delivery_id: f.delivery_id,
          status: f.status,
          status_label: fulfillment_status_label(f.status),
          fulfilled_at: f.fulfilled_at ? l(f.fulfilled_at, format: :short) : nil
        }
      end,
      payment_providers: providers,
      default_provider: providers.first&.dig(:value) || "fake"
    }
  end

  def order_status_label(status)
    ORDER_STATUS_LABELS[status.to_s] || status.to_s.humanize
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

  def refundable_order?(order)
    return false unless %w[paid fulfilled completed].include?(order.status)

    !order.refunds.where(status: %w[pending completed]).exists?
  end

  def fulfillment_status_label(status)
    return nil if status.blank?

    FULFILLMENT_STATUS_LABELS[status.to_s] || status.to_s.humanize
  end

  def compare_product_count
    ids = Array(session[:compare_product_ids])
    Commerce::Product.available.where(public_id: ids).count
  end

  def format_price(product)
    format_money(product.price_cents, product.currency)
  end

  def format_money(cents, currency)
    unit = currency == "CNY" ? "¥" : "$"
    number_to_currency(cents / 100.0, unit: unit)
  end

  def forum_author_name(user)
    return "—" unless user

    name = user.display_name.presence || user.username
    user.forum_title.present? ? "#{name} · #{user.forum_title}" : name
  end

  def number_to_currency(amount, unit:)
    ActionController::Base.helpers.number_to_currency(amount, unit: unit)
  end

  def signed_download_url_for(order_item)
    return nil unless logged_in? && order_item.order.user_id == current_user.id

    result = Commerce::GenerateDownloadToken.call(order_item: order_item, user: current_user)
    return nil unless result.success?

    store_download_path(result.value[:token])
  end
end
