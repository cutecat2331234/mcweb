<script setup lang="ts">
import { Link, usePage } from '@inertiajs/vue3'
import { Moon, Sun } from '@lucide/vue'
import { computed } from 'vue'
import { adminRoutes } from '@/lib/adminRoutes'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import Button from '@/components/ui/Button.vue'

const page = usePage()
const auth = computed(() => page.props.auth as { user: { username: string } | null })

const nav = [
  { label: '概览', items: [
    { label: '仪表盘', href: adminRoutes.dashboard },
    { label: '用户', href: adminRoutes.users },
    { label: '角色', href: adminRoutes.roles },
  ]},
  { label: '官网', items: [
    { label: '页面', href: adminRoutes.websitePages },
    { label: '文章', href: adminRoutes.websiteArticles },
  ]},
  { label: '社区', items: [
    { label: '板块', href: adminRoutes.forumSections },
    { label: '分类', href: adminRoutes.forumCategories },
    { label: '主题', href: adminRoutes.forumTopics },
    { label: '举报', href: adminRoutes.forumReports },
    { label: '徽章', href: adminRoutes.forumBadges },
    { label: '标签', href: adminRoutes.forumTags },
    { label: '论坛设置', href: adminRoutes.forumSettings },
    { label: 'Webhook 投递', href: adminRoutes.forumWebhookDeliveries },
  ]},
  { label: '商城', items: [
    { label: '商品', href: adminRoutes.storeProducts },
    { label: '分类', href: adminRoutes.storeCategories },
    { label: '优惠券', href: adminRoutes.storeCoupons },
    { label: '礼品卡', href: adminRoutes.storeGiftCards },
    { label: '订单', href: adminRoutes.storeOrders },
    { label: '评价', href: adminRoutes.storeReviews },
    { label: '商品问答', href: adminRoutes.storeProductQuestions },
    { label: '发货', href: adminRoutes.storeFulfillments },
    { label: '商城设置', href: adminRoutes.storeSettings },
  ]},
  { label: '系统', items: [
    { label: 'Minecraft 服务器', href: adminRoutes.minecraftServers },
    { label: '审计日志', href: adminRoutes.auditLogs },
    { label: 'IP 封禁', href: adminRoutes.ipBans },
    { label: '设置', href: adminRoutes.settings },
    { label: '后台任务', href: adminRoutes.jobs },
  ]},
]

const isDark = computed(() => document.documentElement.classList.contains('dark'))

function toggleTheme() {
  const next = isDark.value ? 'light' : 'dark'
  document.documentElement.classList.toggle('dark', next === 'dark')
  localStorage.setItem('mc-theme', next)
}
</script>

<template>
  <div class="flex min-h-dvh bg-background">
    <aside class="hidden w-56 shrink-0 border-r bg-card md:block">
      <div class="border-b px-4 py-3">
        <Link :href="adminRoutes.dashboard" class="text-sm font-semibold no-underline text-foreground">
          Mcweb Admin
        </Link>
      </div>
      <nav class="space-y-4 p-3">
        <div v-for="group in nav" :key="group.label">
          <p class="px-2 py-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            {{ group.label }}
          </p>
          <Link
            v-for="item in group.items"
            :key="item.href"
            :href="item.href"
            class="block rounded-md px-2 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            {{ item.label }}
          </Link>
        </div>
      </nav>
      <div class="mt-auto border-t px-4 py-3 text-xs text-muted-foreground">
        <span v-if="auth.user">{{ auth.user.username }}</span>
        <span v-if="auth.user"> · </span>
        <Link :href="adminRoutes.site" class="hover:text-foreground">返回站点</Link>
      </div>
    </aside>

    <div class="flex min-w-0 flex-1 flex-col">
      <header class="flex h-14 items-center justify-between border-b px-4">
        <span class="text-sm text-muted-foreground">管理后台</span>
        <Button variant="ghost" size="icon" type="button" aria-label="切换主题" @click="toggleTheme">
          <Sun v-if="isDark" class="h-4 w-4" />
          <Moon v-else class="h-4 w-4" />
        </Button>
      </header>
      <main class="flex-1 overflow-auto p-4 md:p-6">
        <FlashMessages />
        <slot />
      </main>
    </div>
  </div>
</template>
