<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { ChevronDown, Menu, Moon, Sun, X } from '@lucide/vue'
import Button from '@/components/ui/Button.vue'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import LanguageSwitcher from '@/components/portal/LanguageSwitcher.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { useTheme } from '@/lib/useTheme'

const page = usePage()
const { t } = useI18n()
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const { isDark, toggleTheme } = useTheme()

const STORAGE_KEY = 'mc-admin-nav-expanded'
const mobileNavOpen = ref(false)

const nav = computed(() => [
  { label: t('admin.overview'), items: [
    { label: t('admin.dashboard'), href: adminRoutes.dashboard },
    { label: t('admin.users'), href: adminRoutes.users },
    { label: t('admin.roles'), href: adminRoutes.roles },
  ]},
  { label: t('admin.website'), items: [
    { label: t('admin.pages'), href: adminRoutes.websitePages },
    { label: t('admin.articles'), href: adminRoutes.websiteArticles },
    { label: t('admin.website.nav.title', 'Navigation'), href: adminRoutes.websiteNavItems },
    { label: t('admin.website.themes.title', 'Themes'), href: adminRoutes.websiteThemes },
    { label: t('admin.frontendTemplates'), href: adminRoutes.frontendTemplates },
  ]},
  { label: t('admin.community'), items: [
    { label: t('admin.forumStats'), href: adminRoutes.forumStats },
    { label: t('admin.forumSections'), href: adminRoutes.forumSections },
    { label: t('admin.forumCategories'), href: adminRoutes.forumCategories },
    { label: t('admin.forumTopics'), href: adminRoutes.forumTopics },
    { label: t('admin.forumReports'), href: adminRoutes.forumReports },
    { label: t('admin.forumApprovals'), href: adminRoutes.forumApprovals },
    { label: t('admin.forumUserFields'), href: adminRoutes.forumUserFields },
    { label: t('admin.forumBadges'), href: adminRoutes.forumBadges },
    { label: t('admin.forumWarningTemplates'), href: adminRoutes.forumWarningTemplates },
    { label: t('admin.forumUserTitles'), href: adminRoutes.forumUserTitles },
    { label: t('admin.forumUserGroups'), href: adminRoutes.forumUserGroups },
    { label: t('admin.forumNotices'), href: adminRoutes.forumNotices },
    { label: t('admin.forumHelpArticles'), href: adminRoutes.forumHelpArticles },
    { label: t('admin.forumSmilies'), href: adminRoutes.forumSmilies },
    { label: t('admin.forumCustomBbcodes'), href: adminRoutes.forumCustomBbcodes },
    { label: t('admin.forumThemes'), href: adminRoutes.forumThemes },
    { label: t('admin.forumAttachments'), href: adminRoutes.forumAttachments },
    { label: t('admin.forumScheduledTasks'), href: adminRoutes.forumScheduledTasks },
    { label: t('admin.forumTags'), href: adminRoutes.forumTags },
    { label: t('admin.forumSettings'), href: adminRoutes.forumSettings },
    { label: t('admin.forumWebhookDeliveries'), href: adminRoutes.forumWebhookDeliveries },
    { label: t('admin.forumEventWebhookDeliveries'), href: adminRoutes.forumEventWebhookDeliveries },
  ]},
  { label: t('admin.store'), items: [
    { label: t('admin.storeProducts'), href: adminRoutes.storeProducts },
    { label: t('admin.storeCategories'), href: adminRoutes.storeCategories },
    { label: t('admin.storeCoupons'), href: adminRoutes.storeCoupons },
    { label: t('admin.storeMembershipTypes'), href: adminRoutes.storeMembershipTypes },
    { label: t('admin.storeUserMemberships'), href: adminRoutes.storeUserMemberships },
    { label: t('admin.storeGiftCards'), href: adminRoutes.storeGiftCards },
    { label: t('admin.storeOrders'), href: adminRoutes.storeOrders },
    { label: t('admin.storeWebhookDeliveries'), href: adminRoutes.storeWebhookDeliveries },
    { label: t('admin.storeReviews'), href: adminRoutes.storeReviews },
    { label: t('admin.storeProductQuestions'), href: adminRoutes.storeProductQuestions },
    { label: t('admin.storeFulfillments'), href: adminRoutes.storeFulfillments },
    { label: t('admin.storeSettings'), href: adminRoutes.storeSettings },
  ]},
  { label: t('admin.system'), items: [
    { label: t('admin.minecraftServers'), href: adminRoutes.minecraftServers },
    { label: t('admin.minecraftNodes'), href: adminRoutes.minecraftNodes },
    { label: t('admin.minecraftPlayers'), href: adminRoutes.minecraftPlayers },
    { label: t('admin.minecraftSettings'), href: adminRoutes.minecraftSettings },
    { label: t('admin.minecraftIntegrationActions'), href: adminRoutes.minecraftIntegrationActions },
    { label: t('admin.minecraftProfileFields'), href: adminRoutes.minecraftProfileFields },
    { label: t('admin.minecraftPermissionMappings'), href: adminRoutes.minecraftPermissionMappings },
    { label: t('admin.auditLogs'), href: adminRoutes.auditLogs },
    { label: t('admin.ipBans'), href: adminRoutes.ipBans },
    { label: t('admin.emailBans'), href: adminRoutes.emailBans },
    { label: t('admin.featureToggles'), href: adminRoutes.featureToggles },
    { label: t('admin.applications.nav'), href: adminRoutes.applications },
    { label: t('admin.settings'), href: adminRoutes.settings },
    { label: t('admin.jobs'), href: adminRoutes.jobs },
  ]},
])

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
  for (const group of nav.value) {
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
        <Link :href="adminRoutes.site" class="hover:text-foreground">{{ t('common.backToSite') }}</Link>
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
          <Button variant="ghost" size="icon" type="button" :aria-label="t('common.close')" @click="closeMobileNav">
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
            :aria-label="t('common.openMenu')"
            @click="mobileNavOpen = true"
          >
            <Menu class="h-5 w-5" />
          </Button>
          <span class="text-sm text-muted-foreground">{{ t('common.adminPanel') }}</span>
        </div>
        <div class="flex items-center gap-1">
          <LanguageSwitcher />
          <Button variant="ghost" size="icon" type="button" :aria-label="t('common.toggleTheme')" @click="toggleTheme">
          <Sun v-if="isDark" class="h-4 w-4" />
          <Moon v-else class="h-4 w-4" />
        </Button>
        </div>
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

