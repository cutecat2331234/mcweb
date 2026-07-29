# frozen_string_literal: true

module Admin
  # POC — Element Plus "Overview" facade for the backend redesign.
  #
  # Mounted at /admin/dashboard_pro_demo, isolated from the live dashboard
  # (Admin::DashboardController → Admin/Dashboard/Index). Renders a static demo
  # page (stat cards + recent-orders mini table) carried by the EP ProLayout so
  # the whole unified language can be screenshotted in one shot. Performs NO
  # database reads/writes. Safe to delete once the redesign is signed off.
  class DashboardProDemoController < BaseController
    prepend_before_action :require_admin_demo!

    def index
      render inertia: "Admin/DashboardProDemo", props: {
        title: "概览",
        subtitle: "Element Plus 布局 + 卡片 + 表格一套语言的门面（演示数据，不影响真实后台）"
      }
    end
  end
end
