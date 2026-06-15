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
      email: current_user.email,
      can_upload_images: Community::TrustLevel.can_upload_images?(current_user)
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
      category_icon: section.category&.icon,
      category_color_hex: section.category&.color_hex,
      color_hex: section.color_hex,
      icon: section.icon,
      topics_count: section.topics.where(status: :published).count,
      unread_count: unread_map[section.id].to_i,
      url: forum_section_path(section)
    }

    if include_children && section.children.any?
      data[:children] = section.children.ordered.map { |child| serialize_section(child, include_children: false, unread_map: unread_map) }
    end

    data
  end

  def serialize_topic(topic, read_state: nil, highlight_query: nil)
    unread_count = if read_state
                     read_state.unread_count
    elsif current_user
                     0
    else
                     0
    end

    title_highlight = Community::HighlightSearchText.call(text: topic.title, query: highlight_query) if highlight_query.present?

    {
      id: topic.public_id,
      title: topic.title,
      title_html: title_highlight&.success? ? title_highlight.value[:html] : nil,
      url: forum_topic_path(topic),
      author: topic.user&.username,
      replies_count: topic.replies_count,
      views_count: topic.views_count,
      last_posted_at: topic.last_posted_at ? l(topic.last_posted_at, format: :short) : nil,
      last_poster_username: topic.last_post_user&.username,
      last_poster_url: topic.last_post_user ? forum_user_path(topic.last_post_user.username) : nil,
      pinned: topic.pinned?,
      prefix: topic.prefix,
      locked: topic.locked?,
      featured: topic.featured?,
      wiki: topic.wiki?,
      global_announcement: topic.global_announcement?,
      unlisted: topic.unlisted?,
      archived: topic.archived_at.present?,
      solved: topic.solved_post_id.present?,
      assigned_username: topic.assigned_to&.username,
      assigned_url: topic.assigned_to ? forum_user_path(topic.assigned_to.username) : nil,
      unread_count: unread_count,
      has_unread: unread_count.positive?,
      participant_avatars: topic.participant_users(limit: 5).map do |user|
        { username: user.username, avatar_url: user.avatar_url, profile_url: forum_user_path(user.username) }
      end,
      tags: topic.association(:tags).loaded? ? topic.tags.first(3).map { |tag| serialize_topic_tag(tag) } : [],
      excerpt: topic_list_excerpt(topic),
      thumbnail_url: topic_list_thumbnail(topic)
    }.merge(linked_product_props(topic))
  end

  def topic_list_excerpt(topic)
    body = topic_first_post_body(topic)
    body&.truncate(120)
  end

  def topic_list_thumbnail(topic)
    body = topic_first_post_body(topic).to_s
    match = body.match(/!\[[^\]]*\]\(([^)]+)\)/)
    match&.[](1)
  end

  def topic_first_post_body(topic)
    if topic.association(:posts).loaded?
      topic.posts.min_by(&:floor_number)&.body
    else
      topic.posts.order(:floor_number).pick(:body)
    end
  end

  def linked_product_props(topic)
    product = topic.association(:linked_product).loaded? ? topic.linked_product : Commerce::Product.find_by(forum_topic_id: topic.id)
    return {} unless product

    {
      linked_product: true,
      linked_product_name: product.name,
      linked_product_url: store_product_path(product)
    }
  end

  def serialize_topic_detail(topic, watching: false, notification_level: nil, bookmarked: false, muted: false, can_moderate: false, can_move: false, can_edit: false, viewer: nil)
    {
      id: topic.public_id,
      title: topic.title,
      author: topic.user ? forum_author_name(topic.user) : nil,
      author_username: topic.user&.username,
      author_url: topic.user ? forum_user_path(topic.user.username) : nil,
      locked: topic.locked?,
      lock_reason: topic.lock_reason,
      pinned: topic.pinned?,
      pinned_until: topic.pinned_until ? l(topic.pinned_until, format: :short) : nil,
      bumped_at: topic.bumped_at ? l(topic.bumped_at, format: :short) : nil,
      hidden: topic.status == "hidden",
      featured: topic.featured?,
      wiki: topic.wiki?,
      unlisted: topic.unlisted?,
      archived_at: topic.archived_at ? l(topic.archived_at, format: :short) : nil,
      global_announcement: topic.global_announcement?,
      slow_mode_seconds: topic.slow_mode_seconds,
      auto_close_at: topic.auto_close_at ? l(topic.auto_close_at, format: :short) : nil,
      auto_open_at: topic.auto_open_at ? l(topic.auto_open_at, format: :short) : nil,
      auto_bump_at: topic.auto_bump_at ? l(topic.auto_bump_at, format: :short) : nil,
      auto_archive_at: topic.auto_archive_at ? l(topic.auto_archive_at, format: :short) : nil,
      solved_post_id: topic.solved_post_id,
      assigned_username: topic.assigned_to&.username,
      assigned_url: topic.assigned_to ? forum_user_path(topic.assigned_to.username) : nil,
      views_count: topic.views_count,
      watching: watching,
      notification_level: notification_level,
      muted: muted,
      bookmarked: bookmarked,
      can_moderate: can_moderate,
      can_move: can_move,
      can_edit: can_edit,
      tags: topic.tags.map { |tag| serialize_topic_tag(tag) },
      tags_string: topic.tags.map(&:name).join(", "),
      section: {
        name: topic.section.name,
        slug: topic.section.slug,
        url: forum_section_path(topic.section),
        color_hex: topic.section.color_hex,
        icon: topic.section.icon
      },
      source_topic: source_topic_props(topic)
    }.merge(linked_product_props(topic)).merge(bump_props(topic, can_moderate: can_moderate)).merge(slow_mode_props(topic, user: viewer)).merge(reading_time_props(topic))
  end

  def source_topic_props(topic)
    return nil unless topic.source_post_id.present?

    source_post = topic.association(:source_post).loaded? ? topic.source_post : Community::Post.find_by(id: topic.source_post_id)
    return nil unless source_post

    source = source_post.topic
    {
      title: source.title,
      url: forum_topic_path(source, anchor: "post-#{source_post.id}"),
      floor_number: source_post.floor_number,
      author: source_post.user.username
    }
  end

  def reading_time_props(topic)
    result = Community::EstimateReadingTime.call(topic: topic)
    return {} unless result.success? && result.value[:minutes].to_i.positive?

    { reading_time_minutes: result.value[:minutes] }
  end

  def slow_mode_props(topic, user:)
    seconds = topic.slow_mode_seconds.to_i
    return {} unless user && seconds.positive?

    last_in_topic = topic.posts.where(user: user).order(created_at: :desc).first
    return {} unless last_in_topic

    remaining = seconds - (Time.current - last_in_topic.created_at).to_i
    remaining.positive? ? { slow_mode_remaining_seconds: remaining } : {}
  end

  def bump_props(topic, can_moderate:)
    return {} unless can_moderate

    cooldown_hours = SiteSetting.get("forum.bump_cooldown_hours", "24").to_i
    remaining = if cooldown_hours.positive? && topic.bumped_at && topic.bumped_at > cooldown_hours.hours.ago
                  ((topic.bumped_at + cooldown_hours.hours) - Time.current).to_i
    else
                  0
    end
    { bump_cooldown_remaining_seconds: remaining.positive? ? remaining : nil }
  end

  def serialize_post(post, current_user: nil, can_moderate: false, solved_post_id: nil, post_bookmark: nil)
    formatted = Community::FormatPostBody.call(body: post.body)
    body_html = formatted.success? ? formatted.value : ERB::Util.html_escape(post.body)
    body_long = post.body.length > 800
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

    last_edit = post.edits.order(created_at: :desc).first
    edit_diff_lines = if last_edit
                        diff = Community::DiffLines.call(before_text: last_edit.body_before, after_text: last_edit.body_after)
                        diff.success? ? diff.value : nil
    end

    {
      id: post.id,
      floor_number: post.floor_number,
      parent_post_id: post.parent_post_id,
      depth: post_depth(post),
      is_solved: solved_post_id == post.id,
      author: forum_author_name(post.user),
      author_username: post.user.username,
      author_flair_color: post.user.forum_flair_color_hex.presence,
      author_forum_title: post.user.forum_title.presence,
      author_url: forum_user_path(post.user.username),
      author_card_url: card_forum_user_path(post.user.username),
      author_badges: serialize_user_badges(post.user),
      verified_purchaser: verified_purchaser?(post.user),
      avatar_url: post.user.avatar_url,
      body: post.body,
      body_html: body_html,
      body_long: body_long,
      edit_seconds_remaining: edit_seconds_remaining(post, current_user),
      edit_diff_lines: edit_diff_lines,
      signature_html: signature_html,
      created_at: l(post.created_at, format: :short),
      edited_at: post.edited_at ? l(post.edited_at, format: :short) : nil,
      last_edit_reason: last_edit&.reason.presence,
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
      deleted: post.deleted_at.present?,
      small_action: post.small_action?,
      whisper: post.whisper?,
      wiki: post.wiki_post?,
      staff_notice: post.staff_notice.presence,
      restore_url: (can_moderate && post.deleted_at.present?) ? restore_forum_post_path(post) : nil,
      report_url: current_user ? new_forum_report_path(reportable_type: "Community::Post", reportable_id: post.id) : nil,
      raw_url: raw_forum_post_path(post),
      fork_topic_url: current_user ? fork_topic_forum_post_path(post) : nil,
      forked_topics: post.forked_topics.map { |topic|
        { id: topic.public_id, title: topic.title, url: forum_topic_path(topic) }
      },
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

  def edit_seconds_remaining(post, user)
    return nil unless user && user.id == post.user_id
    return nil if user.permission?("forum.topics.lock") || post.topic.wiki?

    window = Community::TrustLevel.edit_window_for(user)
    return nil if window.nil?

    expires_at = post.created_at + window
    remaining = (expires_at - Time.current).to_i
    remaining.positive? ? remaining : nil
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

  def serialize_search_post(post, query: nil)
    excerpt = post.body.truncate(120)
    highlight = Community::HighlightSearchText.call(text: excerpt, query: query) if query.present?
    {
      id: post.id,
      body: excerpt,
      body_html: highlight&.success? ? highlight.value[:html] : nil,
      author: post.user.username,
      topic_title: post.topic.title,
      topic_url: Community::PostPermalink.path(post.topic, post),
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

  def serialize_user_badges(user, limit: 3)
    return [] unless user

    user.user_badges.includes(:badge).order(granted_at: :desc).limit(limit).map do |ub|
      {
        name: ub.badge.name,
        icon: ub.badge.icon,
        color: ub.badge.color
      }
    end
  end

  def serialize_product_list_item(product)
    avg = product.reviews.published.average(:rating)&.round(1)
    {
      db_id: product.id,
      id: product.public_id,
      name: product.name,
      slug: product.slug,
      summary: product.summary,
      category_name: product.category&.name,
      price_label: format_price(product),
      compare_at_label: product.on_sale? ? format_money(product.compare_at_price_cents, product.currency) : nil,
      on_sale: product.on_sale?,
      discount_percent: product.discount_percent,
      discount_label: product.discount_percent ? "-#{product.discount_percent}%" : nil,
      in_stock: product.in_stock?,
      backorder_available: product.backorder_available?,
      low_stock: product.low_stock?,
      average_rating: avg,
      image_url: product_image_url(product),
      url: store_product_path(product),
      quick_addable: product.variants.none? && product.purchasable?
    }
  end

  def serialize_upcoming_product(product, availability_alert: false, availability_alert_id: nil)
    serialize_product_list_item(product).merge(
      coming_soon: true,
      available_at_label: product.available_at ? l(product.available_at, format: :short) : nil,
      coming_soon_label: product.coming_soon_label,
      preview_url: preview_store_product_path(product),
      has_availability_alert: availability_alert,
      availability_alert_url: logged_in? ? availability_alert_store_product_path(product) : nil,
      availability_alert_unsubscribe_url: availability_alert_id ? store_availability_alert_path(availability_alert_id) : nil
    )
  end

  def serialize_topic_tag(tag)
    effective = tag.effective_tag
    group = effective.tag_groups.first
    {
      name: effective.name,
      slug: effective.slug,
      url: forum_tag_path(effective.slug),
      color_hex: effective.color_hex.presence,
      group_color_hex: group&.color_hex.presence
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
      summary: product.summary,
      price_label: format_price(product),
      compare_at_label: product.on_sale? ? format_money(product.compare_at_price_cents, product.currency) : nil,
      on_sale: product.on_sale?,
      discount_percent: product.discount_percent,
      discount_label: product.discount_percent ? "-#{product.discount_percent}%" : nil,
      product_type: product.product_type,
      category_name: product.category&.name,
      in_stock: product.in_stock?,
      backorder_available: product.backorder_available?,
      low_stock: product.low_stock?,
      purchase_limit: product.purchase_limit,
      minimum_quantity: [ product.minimum_quantity.to_i, 1 ].max,
      maximum_quantity: product.maximum_quantity,
      image_url: product_image_url(product),
      gallery_urls: product.gallery_urls || [],
      version: product.version,
      changelog: product.changelog,
      view_count: product.view_count,
      wishlisted: wishlisted,
      average_rating: average_rating,
      variants: product.variants.map { |variant| serialize_variant(variant, product) },
      reviews: reviews.map { |review| serialize_review(review, current_user: current_user) }
    }.merge(product_discussion_props(product)).merge(product_seo_props(product))
  end

  def product_seo_props(product)
    seo = product.seo || {}
    title = seo["title"].presence || product.name
    description = seo["description"].presence || product.summary.presence || product.description&.truncate(160)
    image = product.image_url.presence
    image ||= url_for(product.cover_image) if product.cover_image.attached?
    {
      seo_title: title,
      seo_description: description,
      seo_image: image
    }
  end

  def product_discussion_props(product)
    topic = product.forum_topic
    if topic
      {
        discussion_url: forum_topic_path(topic),
        discussion_replies_count: topic.replies_count
      }
    else
      { discussion_url: nil, discussion_replies_count: nil }
    end
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
      report_url: current_user && current_user.id != review.user_id ? new_forum_report_path(reportable_type: "Commerce::Review", reportable_id: review.id) : nil,
      verified_purchaser: verified,
      merchant_reply: review.merchant_reply,
      merchant_replied_at: review.merchant_replied_at ? l(review.merchant_replied_at, format: :short) : nil,
      photo_urls: review.photos.map { |photo| rails_blob_path(photo, only_path: true) },
      forum_post_url: review.forum_post ? "#{forum_topic_path(review.forum_post.topic)}#post-#{review.forum_post_id}" : nil,
      can_share_to_forum: current_user && current_user.id == review.user_id && review.forum_post_id.blank?,
      share_to_forum_url: current_user && current_user.id == review.user_id && review.forum_post_id.blank? ? share_to_forum_store_product_review_path(review.product.public_id, review.id) : nil
    }
  end

  def serialize_poll(poll)
    user_votes = poll.votes.where(user: current_user)
    user_vote_indices = user_votes.pluck(:option_index)
    show_results = !poll.hide_results_until_vote || user_votes.exists? || !poll.open?
    can_close = logged_in? && (current_user.id == poll.topic.user_id || current_user.permission?("forum.topics.lock"))
    can_see_voters = show_results && (!poll.anonymous? || current_user&.permission?("forum.topics.lock"))
    {
      id: poll.id,
      question: poll.question,
      open: poll.open?,
      multiple_choice: poll.multiple_choice?,
      max_choices: poll.max_choices,
      hide_results_until_vote: poll.hide_results_until_vote,
      anonymous: poll.anonymous?,
      show_results: show_results,
      options: poll.options.each_with_index.map { |label, index| { label: label, index: index } },
      results: show_results ? poll.results : [],
      total_votes: show_results ? poll.total_votes : nil,
      user_vote_index: user_vote_indices.first,
      user_vote_indices: user_vote_indices,
      vote_url: forum_poll_vote_path(poll),
      revoke_url: poll.open? && user_votes.exists? ? revoke_forum_poll_path(poll) : nil,
      voters_url: can_see_voters ? voters_forum_poll_path(poll) : nil,
      export_url: can_close ? export_forum_poll_path(poll) : nil,
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
      compare_at_label: variant.on_sale? ? format_money(variant.compare_at_price_cents, product.currency) : nil,
      on_sale: variant.on_sale?,
      discount_percent: variant.discount_percent,
      in_stock: variant.in_stock?,
      low_stock: variant.low_stock?
    }
  end

  def serialize_category(category, **query)
    {
      slug: category.slug,
      name: category.name,
      icon: category.icon,
      color_hex: category.color_hex,
      product_count: Commerce::Product.available.where(store_category_id: category.id).count,
      url: store_category_path(category.slug, **query.compact)
    }
  end

  def serialize_cart_item(item)
    unit = item.product.currency == "CNY" ? "¥" : "$"
    unit_cents = item.variant&.price_cents || item.product.price_cents
    limit_data = logged_in? ? Commerce::PurchaseLimitRemaining.call(user: current_user, product: item.product) : nil
    remaining = limit_data&.success? ? limit_data.value[:remaining] : nil
    {
      id: item.id,
      product_name: item.product.name,
      variant_name: item.variant&.name,
      quantity: item.quantity,
      minimum_quantity: [ item.product.minimum_quantity.to_i, 1 ].max,
      maximum_quantity: item.product.maximum_quantity,
      purchase_limit_remaining: remaining,
      unit_price_label: number_to_currency(unit_cents / 100.0, unit: unit),
      total_label: number_to_currency(item.total_cents / 100.0, unit: unit),
      product_url: store_product_path(item.product),
      gift_note: item.gift_note,
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
      shipping_address: order.shipping_address.presence,
      shipping_address_label: format_shipping_address(order.shipping_address),
      shipping_method: order.shipping_method,
      shipping_method_label: Commerce::ShippingMethods.label_for(order.shipping_method),
      tracking_number: order.tracking_number,
      shipping_carrier: order.shipping_carrier,
      shipped_at: order.shipped_at ? l(order.shipped_at, format: :short) : nil,
      tracking_url: tracking_url_for(order),
      packing_slip_url: packing_slip_store_order_path(order),
      subtotal_label: format_money(order.subtotal_cents, order.currency),
      shipping_label: order.shipping_cents.positive? ? format_money(order.shipping_cents, order.currency) : nil,
      free_shipping: order.shipping_cents.zero? && order.subtotal_cents.positive?,
      discount_label: order.discount_cents.positive? ? format_money(order.discount_cents, order.currency) : nil,
      coupon_code: order.coupon&.code,
      gift_card_code: order.gift_card&.code,
      gift_card_amount_label: order.gift_card_amount_cents.positive? ? format_money(order.gift_card_amount_cents, order.currency) : nil,
      store_credit_amount_label: order.store_credit_amount_cents.positive? ? format_money(order.store_credit_amount_cents, order.currency) : nil,
      customer_notes: order.staff_notes.where(visible_to_customer: true).recent.map do |note|
        {
          body: note.body,
          author: note.author.username,
          created_at: l(note.created_at, format: :short)
        }
      end,
      gift_wrap: order.gift_wrap?,
      gift_wrap_label: order.gift_wrap_cents.positive? ? format_money(order.gift_wrap_cents, order.currency) : nil,
      total_label: format_money(order.total_cents, order.currency),
      receipt_url: receipt_store_order_path(order),
      receipt_pdf_url: receipt_pdf_store_order_path(order),
      can_pay: (order.pending? || order.awaiting_payment?) && order.total_cents.positive?,
      can_confirm_free: (order.pending? || order.awaiting_payment?) && order.total_cents.zero?,
      can_cancel: order.pending? || order.awaiting_payment?,
      can_request_refund: refundable_order?(order),
      refund_window_expires_at: refund_window_expires_at(order),
      refund_window_expires_label: refund_window_expires_label(order),
      max_refund_cents: max_refundable_cents(order),
      max_refund_label: format_money(max_refundable_cents(order), order.currency),
      refund_pending: order.refunds.pending.exists?,
      can_download_receipt: %w[paid processing fulfilling fulfilled completed refunded].include?(order.status),
      refund_url: refund_store_order_path(order),
      restorations: serialize_order_restorations(order),
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
      shipping_timeline: Commerce::OrderShippingTimeline.call(order).map do |step|
        {
          key: step[:key],
          label: step[:label],
          state: step[:state],
          at: step[:at] ? l(step[:at], format: :short) : nil
        }
      end,
      delivery_estimate: order.shipping_method.present? ? Commerce::ShippingMethods.delivery_estimate_label(Commerce::ShippingMethods.find(order.shipping_method)) : nil,
      cancel_url: cancel_store_order_path(order),
      reorder_url: reorder_store_order_path(order),
      can_reorder: order.items.any?,
      items: order.items.map do |item|
        fulfillment = order.fulfillments.find_by(order_item: item)
        snapshot = item.fulfillment_snapshot || {}
        gift_note = snapshot["gift_note"].presence || snapshot[:gift_note].presence
        config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
        download_url = signed_download_url_for(item)
        refresh_download_url = download_url.present? ? refresh_download_store_order_path(order, order_item_id: item.id) : nil
        product = item.product
        item_questions = Commerce::ProductQuestion.where(order_item: item).includes(:answers).order(created_at: :desc)
        issued_cards = Commerce::GiftCard.where(source_order_item_id: item.id).order(:id)
        {
          id: item.id,
          product_name: item.product_name,
          variant_name: item.variant_name,
          quantity: item.quantity,
          gift_note: gift_note,
          total_label: format_money(item.total_cents, order.currency),
          product_url: product ? store_product_path(product) : nil,
          product_public_id: product&.public_id,
          ask_question_url: product ? store_product_path(product, ask: 1, order_item_id: item.id) : nil,
          ask_question_return_order_id: order.public_id,
          questions: item_questions.map { |q| serialize_order_item_question(q) },
          discussion_url: product&.forum_topic ? forum_topic_path(product.forum_topic) : nil,
          fulfillment_status: fulfillment&.status,
          fulfillment_status_label: fulfillment_status_label(fulfillment&.status),
          download_url: download_url,
          refresh_download_url: refresh_download_url,
          issued_gift_cards: issued_cards.map do |card|
            {
              code: card.code,
              balance_label: format_money(card.balance_cents, card.currency),
              url: store_gift_card_path(card.code)
            }
          end
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

  def serialize_order_restorations(order)
    items = []
    if order.store_credit_restored_cents.to_i.positive?
      items << {
        label: "商店余额已恢复",
        amount_label: format_money(order.store_credit_restored_cents, order.currency)
      }
    end
    if order.gift_card_restored_cents.to_i.positive?
      items << {
        label: "礼品卡余额已恢复",
        amount_label: format_money(order.gift_card_restored_cents, order.currency)
      }
    end
    if order.coupon_usage_restored? && order.coupon
      items << {
        label: "优惠券使用次数已恢复",
        amount_label: order.coupon.code
      }
    end
    stock_qty = order.items.sum { |item| item.stock_restored_quantity.to_i }
    if stock_qty.positive?
      items << {
        label: "库存已恢复",
        amount_label: "#{stock_qty} 件"
      }
    end
    items
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
    return false if max_refundable_cents(order) <= 0
    return false unless within_refund_window?(order)

    !order.refunds.pending.exists?
  end

  def within_refund_window?(order)
    window_days = SiteSetting.get("store.refund_window_days", "0").to_i
    return true if window_days <= 0

    payment = order.payment_records.where(status: "succeeded").order(created_at: :asc).first
    return false unless payment

    Time.current <= payment.created_at + window_days.days
  end

  def max_refundable_cents(order)
    payment = order.payment_records.where(status: "succeeded").order(created_at: :desc).first
    return 0 unless payment

    refunded = order.refunds.where(status: %w[pending completed]).sum(:amount_cents)
    [ payment.amount_cents - refunded, 0 ].max
  end

  def refund_window_expires_at(order)
    window_days = SiteSetting.get("store.refund_window_days", "0").to_i
    return nil if window_days <= 0

    payment = order.payment_records.where(status: "succeeded").order(created_at: :asc).first
    return nil unless payment

    payment.created_at + window_days.days
  end

  def refund_window_expires_label(order)
    expires = refund_window_expires_at(order)
    return nil unless expires

    expires.future? ? l(expires, format: :short) : nil
  end

  def fulfillment_status_label(status)
    return nil if status.blank?

    FULFILLMENT_STATUS_LABELS[status.to_s] || status.to_s.humanize
  end

  def serialize_shipping_quote(subtotal_cents, currency: "CNY", cart_items: nil, coupon: nil, shipping_method_code: nil)
    result = Commerce::CalculateShipping.call(
      subtotal_cents: subtotal_cents,
      cart_items: cart_items,
      coupon: coupon,
      shipping_method_code: shipping_method_code
    )
    return {} unless result.success?

    value = result.value
    {
      shippingCents: value[:shipping_cents],
      shippingLabel: format_money(value[:shipping_cents], currency),
      freeShipping: value[:free_shipping],
      noShippableItems: value[:no_shippable_items] == true,
      couponFreeShipping: value[:coupon_free_shipping] == true,
      freeShippingMinLabel: value[:free_shipping_min_cents].positive? ? format_money(value[:free_shipping_min_cents], currency) : nil,
      freeShippingRemainingLabel: value[:amount_remaining_cents].positive? ? format_money(value[:amount_remaining_cents], currency) : nil,
      shippingMethodCode: value[:shipping_method_code],
      shippingMethodLabel: value[:shipping_method_label],
      shippingMethods: Commerce::ShippingMethods.list.map do |method|
        estimate = Commerce::ShippingMethods.delivery_estimate_label(method)
        price_label = format_money(method["cents"], currency)
        {
          code: method["code"],
          label: method["label"],
          cents: method["cents"],
          delivery_estimate: estimate,
          label_with_price: estimate.present? ? "#{method['label']} (#{price_label}) · #{estimate}" : "#{method['label']} (#{price_label})"
        }
      end
    }
  end

  def compare_product_count
    ids = Array(session[:compare_product_ids])
    Commerce::Product.active.where(public_id: ids).count
  end

  def product_compare_props(product)
    return {} unless logged_in?

    {
      compare_url: store_toggle_compare_path(product_id: product.public_id),
      compared: Array(session[:compare_product_ids]).include?(product.public_id)
    }
  end

  def wishlisted_product_ids
    @wishlisted_product_ids ||= if logged_in?
                                  Commerce::WishlistItem.where(user: current_user).pluck(:store_product_id).to_set
    else
                                  Set.new
    end
  end

  def product_wishlist_props(product)
    return {} unless logged_in?

    {
      wishlist_url: wishlist_store_product_path(product),
      wishlisted: wishlisted_product_ids.include?(product.id)
    }
  end

  def format_price(product)
    format_money(product.price_cents, product.currency)
  end

  def tracking_url_for(order)
    Commerce::TrackingUrl.for_order(order)
  end

  def format_shipping_address(address)
    return nil unless address.is_a?(Hash) && address.values.any?(&:present?)

    parts = [
      address["name"],
      address["phone"],
      [ address["province"], address["city"] ].compact.join(" "),
      [ address["line1"], address["line2"] ].compact.join(" "),
      address["postal_code"]
    ].map(&:presence).compact
    parts.join("，")
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

  def verified_purchaser?(user)
    return false unless user

    Commerce::Order.where(user: user, status: %w[paid processing fulfilling fulfilled completed]).exists?
  end

  def serialize_order_item_question(question)
    {
      id: question.id,
      body: question.body,
      created_at: l(question.created_at, format: :short),
      answers: question.answers.order(created_at: :asc).map do |answer|
        {
          body: answer.body,
          author: answer.user.username,
          official: answer.official,
          created_at: l(answer.created_at, format: :short)
        }
      end
    }
  end
end
