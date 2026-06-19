<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { ChevronDown, Menu, Moon, Sun, X } from '@lucide/vue'
import Button from '@/components/ui/Button.vue'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { useTheme } from '@/lib/useTheme'

const page = usePage()
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const { isDark, toggleTheme } = useTheme()

const STORAGE_KEY = 'mc-admin-nav-expanded'
const mobileNavOpen = ref(false)

const nav = [
  { label: '概览', items: [
    { label: '仪表盘', href: adminRoutes.dashboard },
    { label: '用户', href: adminRoutes.users },
    { label: '角色', href: adminRoutes.roles },
  ]},
  { label: '官网', items: [
    { label: '页面', href: adminRoutes.websitePages },
    { label: '文章', href: adminRoutes.websiteArticles },
    { label: '前台模板', href: adminRoutes.frontendTemplates },
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
    { label: 'Webhook 投递', href: adminRoutes.storeWebhookDeliveries },
    { label: '评价', href: adminRoutes.storeReviews },
    { label: '商品问答', href: adminRoutes.storeProductQuestions },
    { label: '发货', href: adminRoutes.storeFulfillments },
    { label: '商城设置', href: adminRoutes.storeSettings },
  ]},
  { label: '系统', items: [
    { label: 'Minecraft 服务器', href: adminRoutes.minecraftServers },
    { label: '审计日志', href: adminRoutes.auditLogs },
    { label: 'IP 封禁', href: adminRoutes.ipBans },
    { label: '功能开关', href: adminRoutes.featureToggles },
    { label: '设置', href: adminRoutes.settings },
    { label: '后台任务', href: adminRoutes.jobs },
  ]},
]

const expanded = ref<Record<string, boolean>>(loadExpanded())

function loadExpanded() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') as Record<string, boolean>
  } catch {
    return {}
  }
}

function persistExpanded() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(expanded.value))
}

function isGroupExpanded(label: string) {
  return expanded.value[label] ?? false
}

function toggleGroup(label: string) {
  expanded.value = { ...expanded.value, [label]: !isGroupExpanded(label) }
  persistExpanded()
}

function autoExpandActiveGroup() {
  const url = page.url.split('?')[0]
  for (const group of nav) {
    if (group.items.some((item) => url === item.href || url.startsWith(`${item.href}/`))) {
      if (!isGroupExpanded(group.label)) {
        expanded.value = { ...expanded.value, [group.label]: true }
        persistExpanded()
      }
      break
    }
  }
}

watch(() => page.url, autoExpandActiveGroup, { immediate: true })

function closeMobileNav() {
  mobileNavOpen.value = false
}

function isActive(href: string) {
  const url = page.url.split('?')[0]
  return url === href || url.startsWith(`${href}/`)
}
</script>

<template>
  <div class="flex min-h-dvh bg-background">
    <aside class="hidden w-56 shrink-0 border-r bg-card md:flex md:flex-col">
      <div class="border-b px-4 py-3">
        <Link :href="adminRoutes.dashboard" class="text-sm font-semibold no-underline text-foreground">
          Mcweb Admin
        </Link>
      </div>
      <nav class="flex-1 space-y-1 overflow-auto p-3">
        <div v-for="group in nav" :key="group.label" class="rounded-md">
          <button
            type="button"
            class="flex w-full items-center justify-between rounded-md px-2 py-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground hover:bg-muted hover:text-foreground"
            @click="toggleGroup(group.label)"
          >
            <span>{{ group.label }}</span>
            <ChevronDown
              class="h-3.5 w-3.5 transition-transform duration-200"
              :class="isGroupExpanded(group.label) && 'rotate-180'"
            />
          </button>
          <div v-show="isGroupExpanded(group.label)" class="mt-0.5 space-y-0.5">
            <Link
              v-for="item in group.items"
              :key="item.href"
              :href="item.href"
              class="block rounded-md px-2 py-1.5 text-sm transition-colors"
              :class="isActive(item.href)
                ? 'bg-primary/10 font-medium text-primary'
                : 'text-muted-foreground hover:bg-muted hover:text-foreground'"
            >
              {{ item.label }}
            </Link>
          </div>
        </div>
      </nav>
      <div class="border-t px-4 py-3 text-xs text-muted-foreground">
        <span v-if="auth.user">{{ auth.user.username }}</span>
        <span v-if="auth.user"> · </span>
        <Link :href="adminRoutes.site" class="hover:text-foreground">返回站点</Link>
      </div>
    </aside>

    <Transition
      enter-active-class="transition-opacity duration-200"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-200"
      leave-to-class="opacity-0"
    >
      <div
        v-if="mobileNavOpen"
        class="fixed inset-0 z-50 bg-black/50 md:hidden"
        @click="closeMobileNav"
      />
    </Transition>
    <Transition
      enter-active-class="transition-transform duration-200 ease-out"
      enter-from-class="-translate-x-full"
      leave-active-class="transition-transform duration-200 ease-in"
      leave-to-class="-translate-x-full"
    >
      <aside
        v-if="mobileNavOpen"
        class="fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r bg-card md:hidden"
      >
        <div class="flex items-center justify-between border-b px-4 py-3">
          <Link :href="adminRoutes.dashboard" class="text-sm font-semibold no-underline text-foreground" @click="closeMobileNav">
            Mcweb Admin
          </Link>
          <Button variant="ghost" size="icon" type="button" aria-label="关闭菜单" @click="closeMobileNav">
            <X class="h-4 w-4" />
          </Button>
        </div>
        <nav class="flex-1 space-y-1 overflow-auto p-3">
          <div v-for="group in nav" :key="`mobile-${group.label}`" class="rounded-md">
            <button
              type="button"
              class="flex w-full items-center justify-between rounded-md px-2 py-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground hover:bg-muted"
              @click="toggleGroup(group.label)"
            >
              <span>{{ group.label }}</span>
              <ChevronDown class="h-3.5 w-3.5" :class="isGroupExpanded(group.label) && 'rotate-180'" />
            </button>
            <div v-show="isGroupExpanded(group.label)" class="mt-0.5 space-y-0.5">
              <Link
                v-for="item in group.items"
                :key="item.href"
                :href="item.href"
                class="block rounded-md px-2 py-1.5 text-sm text-muted-foreground hover:bg-muted hover:text-foreground"
                @click="closeMobileNav"
              >
                {{ item.label }}
              </Link>
            </div>
          </div>
        </nav>
      </aside>
    </Transition>

    <div class="flex min-w-0 flex-1 flex-col">
      <header class="flex h-14 items-center justify-between border-b px-4">
        <div class="flex items-center gap-2">
          <Button
            variant="ghost"
            size="icon"
            type="button"
            class="md:hidden"
            aria-label="打开菜单"
            @click="mobileNavOpen = true"
          >
            <Menu class="h-5 w-5" />
          </Button>
          <span class="text-sm text-muted-foreground">管理后台</span>
        </div>
        <Button variant="ghost" size="icon" type="button" aria-label="切换主题" @click="toggleTheme">
          <Sun v-if="isDark" class="h-4 w-4" />
          <Moon v-else class="h-4 w-4" />
        </Button>
      </header>
      <main class="flex-1 overflow-auto p-4 md:p-6">
        <div class="mx-auto w-full max-w-6xl">
          <FlashMessages />
          <slot />
        </div>
      </main>
    </div>
  </div>
</template>
