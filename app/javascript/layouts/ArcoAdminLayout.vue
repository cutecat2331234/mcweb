<script setup lang="ts">
/**
 * ArcoAdminLayout — Arco Design shell for McWeb admin (sidebar + navbar + content).
 * Inspired by Arco Pro default-layout; navigation uses Inertia router.visit(), not vue-router.
 */
import { computed, ref, watch } from 'vue'
import { Link, router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  IconApps,
  IconBook,
  IconCommand,
  IconMenuFold,
  IconMenuUnfold,
  IconMoon,
  IconSun,
} from '@arco-design/web-vue/es/icon'
import AdminFlashMessages from '@/components/admin/AdminFlashMessages.vue'
import AdminLanguageSwitcher from '@/components/admin/AdminLanguageSwitcher.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { useTheme } from '@/lib/useTheme'

interface NavItem {
  label: string
  href: string
}
interface NavGroup {
  key: string
  label: string
  items: NavItem[]
}

const page = usePage()
const { t } = useI18n()
const auth = computed(
  () => (page.props.auth ?? { user: null }) as { user: { username: string } | null },
)
const { isDark, toggleTheme } = useTheme()

const STORAGE_KEY = 'mc-admin-arco-nav-open'
const collapsed = ref(false)
const mobileNavOpen = ref(false)

const nav = computed<NavGroup[]>(() => [
  {
    key: 'overview',
    label: t('admin.overview'),
    items: [
      { label: t('admin.dashboard.title'), href: adminRoutes.dashboard },
      { label: t('admin.users'), href: adminRoutes.users },
      { label: t('admin.roles'), href: adminRoutes.roles },
      { label: t('admin.arcoDemo'), href: adminRoutes.arcoDemo },
    ],
  },
  {
    key: 'website',
    label: t('admin.website.title'),
    items: [
      { label: t('admin.pages'), href: adminRoutes.websitePages },
      { label: t('admin.articles'), href: adminRoutes.websiteArticles },
      { label: t('admin.website.nav.title', 'Navigation'), href: adminRoutes.websiteNavItems },
      { label: t('admin.website.themes.title', 'Themes'), href: adminRoutes.websiteThemes },
      { label: t('admin.frontendTemplates'), href: adminRoutes.frontendTemplates },
    ],
  },
  {
    key: 'community',
    label: t('admin.community'),
    items: [
      { label: t('admin.forumStats'), href: adminRoutes.forumStats },
      { label: t('admin.forumSections'), href: adminRoutes.forumSections },
      { label: t('admin.forumCategories'), href: adminRoutes.forumCategories },
      { label: t('admin.forumTopics'), href: adminRoutes.forumTopics },
      { label: t('admin.forumReports'), href: adminRoutes.forumReports },
      { label: t('admin.forumApprovals'), href: adminRoutes.forumApprovals },
      { label: t('admin.forumUserFields'), href: adminRoutes.forumUserFields },
      { label: t('admin.forumTopicFields'), href: adminRoutes.forumTopicFields },
      { label: t('admin.forumBadges'), href: adminRoutes.forumBadges },
      { label: t('admin.forumPoints'), href: adminRoutes.forumPoints },
      { label: t('admin.forumWarningTemplates'), href: adminRoutes.forumWarningTemplates },
      { label: t('admin.forumUserTitles'), href: adminRoutes.forumUserTitles },
      { label: t('admin.forumUserGroups'), href: adminRoutes.forumUserGroups },
      { label: t('admin.forumNotices'), href: adminRoutes.forumNotices },
      { label: t('admin.forumHelpArticles'), href: adminRoutes.forumHelpArticles },
      { label: t('admin.forumSmilies'), href: adminRoutes.forumSmilies },
      { label: t('admin.forumReactionTypes'), href: adminRoutes.forumReactionTypes },
      { label: t('admin.forumCustomBbcodes'), href: adminRoutes.forumCustomBbcodes },
      { label: t('admin.forumThemes'), href: adminRoutes.forumThemes },
      { label: t('admin.forumPages'), href: adminRoutes.forumPages },
      { label: t('admin.forumPhrases'), href: adminRoutes.forumPhrases },
      { label: t('admin.forumAttachments'), href: adminRoutes.forumAttachments },
      { label: t('admin.forumScheduledTasks'), href: adminRoutes.forumScheduledTasks },
      { label: t('admin.forumTags'), href: adminRoutes.forumTags },
      { label: t('admin.forumSettings.title'), href: adminRoutes.forumSettings },
      { label: t('admin.forumWebhookDeliveries'), href: adminRoutes.forumWebhookDeliveries },
      { label: t('admin.forumEventWebhookDeliveries'), href: adminRoutes.forumEventWebhookDeliveries },
    ],
  },
  {
    key: 'store',
    label: t('admin.store'),
    items: [
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
      { label: t('admin.storeSettings.title'), href: adminRoutes.storeSettings },
    ],
  },
  {
    key: 'system',
    label: t('admin.system'),
    items: [
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
      { label: t('admin.systemApiKeys'), href: adminRoutes.systemApiKeys },
      { label: t('admin.systemWebhookSubscriptions'), href: adminRoutes.systemWebhookSubscriptions },
      { label: t('admin.featureToggles.title'), href: adminRoutes.featureToggles },
      { label: t('admin.applications.nav'), href: adminRoutes.applications },
      { label: t('admin.settings'), href: adminRoutes.settings },
      { label: t('admin.jobs'), href: adminRoutes.jobs },
    ],
  },
])

const currentPath = computed(() => {
  const path = page.url.split('?')[0].replace(/\/+$/, '')
  return path || '/'
})

function isActive(href: string) {
  const url = currentPath.value
  if (href === adminRoutes.dashboard) return url === href
  return url === href || url.startsWith(`${href}/`)
}

const activeGroupKey = computed(() => {
  for (const group of nav.value) {
    if (group.items.some((item) => isActive(item.href))) return group.key
  }
  return ''
})

const activeItemHref = computed(() => {
  for (const group of nav.value) {
    const item = group.items.find((candidate) => isActive(candidate.href))
    if (item) return item.href
  }
  return ''
})

const trailingCrumbs = computed<Array<{ label: string }>>(() => {
  for (const group of nav.value) {
    const item = group.items.find((it) => isActive(it.href))
    if (item) return [{ label: group.label }, { label: item.label }]
  }
  const title = page.props.title
  return typeof title === 'string' && title ? [{ label: title }] : []
})

function loadOpen(): string[] {
  try {
    const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]')
    return Array.isArray(raw) ? (raw as string[]) : []
  } catch {
    return []
  }
}

const openKeys = ref<string[]>(loadOpen())

watch(activeGroupKey, (key) => {
  if (key && !openKeys.value.includes(key)) {
    openKeys.value = [...openKeys.value, key]
    localStorage.setItem(STORAGE_KEY, JSON.stringify(openKeys.value))
  }
}, { immediate: true })

watch(openKeys, (keys) => {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(keys))
})

function onMenuClick(key: string) {
  mobileNavOpen.value = false
  if (key && key !== currentPath.value) router.visit(key)
}

function onToggleTheme() {
  toggleTheme()
  syncArcoTheme()
}

function syncArcoTheme() {
  if (typeof document === 'undefined') return
  document.body.setAttribute('arco-theme', isDark.value ? 'dark' : '')
}

watch(isDark, syncArcoTheme, { immediate: true })
</script>

<template>
  <a href="#admin-content" class="arco-admin-skip-link">
    {{ t('common.skipToContent', 'Skip to content') }}
  </a>

  <a-layout class="arco-admin-layout min-h-dvh">
    <a-layout-sider
      class="arco-admin-sider hidden md:block"
      :collapsed="collapsed"
      :width="220"
      :collapsed-width="48"
      collapsible
      :hide-trigger="true"
    >
      <div class="arco-admin-brand">
        <Link :href="adminRoutes.dashboard" class="arco-admin-brand__link">
          <icon-command class="arco-admin-brand__icon" />
          <span v-show="!collapsed" class="arco-admin-brand__text">McWeb Admin</span>
        </Link>
      </div>
      <div class="arco-admin-sider__menu">
        <a-menu
          :selected-keys="activeItemHref ? [activeItemHref] : []"
          v-model:open-keys="openKeys"
          :collapsed="collapsed"
          @menu-item-click="onMenuClick"
        >
          <a-sub-menu v-for="group in nav" :key="group.key">
            <template #icon><icon-apps /></template>
            <template #title>{{ group.label }}</template>
            <a-menu-item v-for="item in group.items" :key="item.href">
              {{ item.label }}
            </a-menu-item>
          </a-sub-menu>
        </a-menu>
      </div>
      <div v-show="!collapsed" class="arco-admin-sider__footer">
        <span v-if="auth.user">{{ auth.user.username }}</span>
        <span v-if="auth.user"> · </span>
        <Link :href="adminRoutes.site">{{ t('common.backToSite') }}</Link>
      </div>
    </a-layout-sider>

    <a-layout>
      <a-layout-header class="arco-admin-header">
        <div class="arco-admin-header__left">
          <a-button
            class="md:hidden"
            type="text"
            :aria-label="t('common.openMenu')"
            @click="mobileNavOpen = true"
          >
            <template #icon><icon-menu-unfold /></template>
          </a-button>
          <a-button
            class="hidden md:inline-flex"
            type="text"
            :aria-label="collapsed ? t('common.openMenu') : t('common.close')"
            @click="collapsed = !collapsed"
          >
            <template #icon>
              <icon-menu-unfold v-if="collapsed" />
              <icon-menu-fold v-else />
            </template>
          </a-button>
          <a-breadcrumb>
            <a-breadcrumb-item>
              <Link :href="adminRoutes.dashboard">{{ t('common.adminPanel') }}</Link>
            </a-breadcrumb-item>
            <a-breadcrumb-item v-for="crumb in trailingCrumbs" :key="crumb.label">
              {{ crumb.label }}
            </a-breadcrumb-item>
          </a-breadcrumb>
        </div>
        <div class="arco-admin-header__right">
          <AdminLanguageSwitcher />
          <a-button type="text" :aria-label="t('common.toggleTheme')" @click="onToggleTheme">
            <template #icon>
              <icon-moon v-if="isDark" />
              <icon-sun v-else />
            </template>
          </a-button>
        </div>
      </a-layout-header>

      <a-layout-content id="admin-content" class="arco-admin-main" tabindex="-1">
        <div class="arco-admin-main__inner">
          <AdminFlashMessages />
          <slot />
        </div>
      </a-layout-content>
    </a-layout>
  </a-layout>

  <a-drawer
    v-model:visible="mobileNavOpen"
    placement="left"
    :width="'min(280px, 100vw)'"
    :footer="false"
    :header="false"
    :aria-label="t('common.openMenu')"
    unmount-on-close
  >
    <div class="arco-admin-brand arco-admin-brand--drawer">
      <Link :href="adminRoutes.dashboard" class="arco-admin-brand__link" @click="mobileNavOpen = false">
        <icon-command class="arco-admin-brand__icon" />
        <span class="arco-admin-brand__text">McWeb Admin</span>
      </Link>
    </div>
    <a-menu
      :selected-keys="activeItemHref ? [activeItemHref] : []"
      v-model:open-keys="openKeys"
      @menu-item-click="onMenuClick"
    >
      <a-sub-menu v-for="group in nav" :key="group.key">
        <template #icon><icon-book /></template>
        <template #title>{{ group.label }}</template>
        <a-menu-item v-for="item in group.items" :key="item.href">
          {{ item.label }}
        </a-menu-item>
      </a-sub-menu>
    </a-menu>
    <div class="arco-admin-sider__footer">
      <span v-if="auth.user">{{ auth.user.username }}</span>
      <span v-if="auth.user"> · </span>
      <Link :href="adminRoutes.site" @click="mobileNavOpen = false">{{ t('common.backToSite') }}</Link>
    </div>
  </a-drawer>
</template>

<style scoped>
.arco-admin-layout {
  background: var(--color-bg-1);
}

.arco-admin-skip-link {
  position: fixed;
  z-index: 1101;
  top: 8px;
  left: 8px;
  padding: 8px 12px;
  color: var(--color-text-1);
  background: var(--color-bg-2);
  border: 1px solid rgb(var(--primary-6));
  border-radius: 4px;
  transform: translateY(-150%);
}
.arco-admin-skip-link:focus {
  transform: translateY(0);
}

.arco-admin-sider {
  position: sticky;
  top: 0;
  height: 100dvh;
  display: flex;
  flex-direction: column;
  border-right: 1px solid var(--color-border-2);
  background: var(--color-bg-2);
}

.arco-admin-brand {
  display: flex;
  align-items: center;
  height: 60px;
  padding: 0 16px;
  border-bottom: 1px solid var(--color-border-2);
}
.arco-admin-brand--drawer {
  margin-bottom: 8px;
}
.arco-admin-brand__link {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  color: var(--color-text-1);
  text-decoration: none;
  font-weight: 600;
  font-size: 15px;
}
.arco-admin-brand__icon {
  font-size: 22px;
  color: rgb(var(--primary-6));
}

.arco-admin-sider__menu {
  flex: 1;
  min-height: 0;
  overflow: auto;
}

.arco-admin-sider__footer {
  padding: 12px 16px;
  font-size: 12px;
  color: var(--color-text-3);
  border-top: 1px solid var(--color-border-2);
}
.arco-admin-sider__footer a {
  color: var(--color-text-3);
  text-decoration: none;
}
.arco-admin-sider__footer a:hover {
  color: rgb(var(--primary-6));
}

.arco-admin-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 60px;
  padding: 0 20px;
  background: var(--color-bg-2);
  border-bottom: 1px solid var(--color-border-2);
}
.arco-admin-header__left,
.arco-admin-header__right {
  display: flex;
  align-items: center;
  gap: 8px;
}

.arco-admin-main {
  min-width: 0;
  padding: 24px;
  overflow: auto;
}
.arco-admin-main__inner {
  max-width: 1200px;
  margin: 0 auto;
}

@media (max-width: 767px) {
  .arco-admin-main {
    padding: 16px;
  }
}
</style>
