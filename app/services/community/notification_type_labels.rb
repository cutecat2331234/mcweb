# frozen_string_literal: true

module Community
  module NotificationTypeLabels
    FORUM = {
      "forum.topic_reply" => "主题回复",
      "forum.mention" => "@提及",
      "forum.section_topic" => "分区新主题",
      "forum.private_message" => "私信",
      "forum.followed_topic" => "关注用户新主题",
      "forum.followed_reply" => "关注用户回复",
      "forum.tag_topic" => "标签新主题",
      "forum.reaction" => "帖子反应",
      "forum.quote" => "帖子引用",
      "forum.topic_solved" => "主题已解决",
      "forum.saved_search_match" => "保存搜索匹配",
      "forum.badge" => "获得徽章",
      "forum.trust_level" => "信任等级",
      "forum.topic_assigned" => "主题指派",
      "forum.post_edited" => "帖子编辑",
      "forum.topic_invite" => "主题邀请",
      "forum.poll_closed" => "投票关闭",
      "forum.here" => "@here 提及"
    }.freeze

    COMMERCE = {
      "commerce.order_created" => "订单创建",
      "commerce.payment_confirmed" => "支付确认",
      "commerce.payment_reminder" => "付款提醒",
      "commerce.order_shipped" => "订单发货",
      "commerce.order_fulfilled" => "订单履约",
      "commerce.order_completed" => "订单完成",
      "commerce.order_cancelled" => "订单取消",
      "commerce.refund_requested" => "退款申请",
      "commerce.refund_processed" => "退款完成",
      "commerce.review_request" => "评价邀请",
      "commerce.merchant_review_reply" => "商家回复评价",
      "commerce.product_available" => "商品到货",
      "commerce.abandoned_cart" => "购物车提醒",
      "commerce.low_stock" => "库存预警"
    }.freeze

    ALL = FORUM.merge(COMMERCE).freeze

    def self.label_for(type)
      ALL[type.to_s] || type.to_s.humanize
    end
  end
end
