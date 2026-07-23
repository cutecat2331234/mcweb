<script setup lang="ts">
/**
 * ProLayout — Element Plus rebuild of the admin shell (sidebar + top bar), the
 * layout half of the "全量 Element Plus" backend redesign. It mirrors every
 * behaviour of the legacy shadcn layouts/AdminLayout.vue (grouped nav, active
 * highlight, auto-expand of the active group, collapsible groups persisted to
 * localStorage, mobile drawer, "username · back to site" footer) but expresses
 * it with el-container / el-aside / el-menu / el-header / el-breadcrumb /
 * el-drawer so it reads as one language with the EP ProTable content.
 *
 * Reused as-is (not rewritten): the nav group/link data + adminRoutes, useTheme
 * (isDark/toggleTheme), LanguageSwitcher.vue, FlashMessages.vue. New on top of
 * the old layout: an el-breadcrumb derived from the current route/group, and
 * @element-plus/icons-vue glyphs on each nav group for visual hierarchy.
 *
 * Navigation goes through Inertia's router.visit (el-menu is NOT in vue-router
 * mode) so the SPA semantics stay identical to the <Link>-based old layout.
 */
import { computed, ref, watch } from 'vue'
import { Link, router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  ChatDotRound,
  Expand,
  Monitor,
  Moon,
  Odometer,
  ShoppingCart,
  Sunny,
  Tools,
} from '@element-plus/icons-vue'
import type { Component } from 'vue'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import LanguageSwitcher from '@/components/portal/LanguageSwitcher.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { useTheme } from '@/lib/useTheme'

interface NavItem {
  label: string
  href: string
}
interface NavGroup {
  key: string
  label: string
  icon: Component
  items: NavItem[]
}

const page = usePage()
const { t } = useI18n()
const auth = computed(() => page.props.auth as { user: { username: string } | null })
const { isDark, toggleTheme } = useTheme()

const STORAGE_KEY = 'mc-admin-pro-nav-openeds'
const mobileNavOpen = ref(false)

/* Nav data ported from layouts/AdminLayout.vue. Only difference: the labels that
 * used to collide with same-named locale content objects (dashboard / website /
 * forumSettings / storeSettings / featureToggles) now read the object's `.title`
 * leaf, and each group carries a stable `key` (used as the el-sub-menu index and
 * icon anchor) so open/active state survives locale switches. */
const nav = computed<NavGroup[]>(() => [
  { key: 'overview', label: t('admin.overview'), icon: Odometer, items: [
    { label: t('admin.dashboard.title'), href: adminRoutes.dashboard },
    { label: t('admin.users'), href: adminRoutes.users },
    { label: t('admin.roles'), href: adminRoutes.roles },
  ] },
  { key: 'website', label: t('admin.website.title'), icon: Monitor, items: [
    { label: t('admin.pages'), href: adminRoutes.websitePages },
    { label: t('admin.articles'), href: adminRoutes.websiteArticles },
    { label: t('admin.website.nav.title'), href: adminRoutes.websiteNavItems },
    { label: t('admin.website.themes.title'), href: adminRoutes.websiteThemes },
    { label: t('admin.frontendTemplates'), href: adminRoutes.frontendTemplates },
  ] },
  { key: 'community', label: t('admin.community'), icon: ChatDotRound, items: [
    { label: t('admin.forumStats'), href: adminRoutes.forumStats },
    { label: t('admin.forumSections'), href: adminRoutes.forumSections },
    { label: t('admin.forumCategories'), href: adminRoutes.forumCategories },
    { label: t('admin.forumTopics'), href: adminRoutes.forumTopics },
    { label: t('admin.forumReports'), href: adminRoutes.forumReports },
    { label: t('admin.forumApprovals'), href: adminRoutes.forumApprovals },
    { label: t('admin.forumUserFields'), href: adminRoutes.forumUserFields },
    { label: t('admin.forumBadges'), href: adminRoutes.forumBadges },
    { label: t('admin.forumPoints'), href: adminRoutes.forumPoints },
    { label: t('admin.forumWarningTemplates'), href: adminRoutes.forumWarningTemplates },
    { label: t('admin.forumUserTitles'), href: adminRoutes.forumUserTitles },
    { label: t('admin.forumUserGroups'), href: adminRoutes.forumUserGroups },
    { label: t('admin.forumNotices'), href: adminRoutes.forumNotices },
    { label: t('admin.forumHelpArticles'), href: adminRoutes.forumHelpArticles },
    { label: t('admin.forumSmilies'), href: adminRoutes.forumSmilies },
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
  ] },
  { key: 'store', label: t('admin.store'), icon: ShoppingCart, items: [
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
  ] },
  { key: 'system', label: t('admin.system'), icon: Tools, items: [
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
    { label: t('admin.featureToggles.title'), href: adminRoutes.featureToggles },
    { label: t('admin.applications.nav'), href: adminRoutes.applications },
    { label: t('admin.settings'), href: adminRoutes.settings },
    { label: t('admin.jobs'), href: adminRoutes.jobs },
  ] },
])

const currentPath = computed(() => page.url.split('?')[0])

function isActive(href: string) {
  const url = currentPath.value
  // Dashboard lives at the /admin root, so a startsWith test would light up on
  // every /admin/* page — match it exactly, prefix-match everything else.
  if (href === adminRoutes.dashboard) return url === href
  return url === href || url.startsWith(`${href}/`)
}

const activeGroupKey = computed(() => {
  for (const group of nav.value) {
    if (group.items.some((item) => isActive(item.href))) return group.key
  }
  return ''
})

/* Breadcrumb (new vs the old layout): root → active group → active item, derived
 * from the current route. Demo pages that aren't in the nav fall back to the
 * page's own `title` prop so the trail is never empty. */
const trailingCrumbs = computed<Array<{ label: string }>>(() => {
  for (const group of nav.value) {
    const item = group.items.find((it) => isActive(it.href))
    if (item) return [{ label: group.label }, { label: item.label }]
  }
  const title = page.props.title
  return typeof title === 'string' && title ? [{ label: title }] : []
})

/* Collapsible groups, persisted like the old layout (localStorage), merged with
 * the active group so navigating always reveals where you are. el-menu owns the
 * open state; we mirror it back to storage via @open/@close and re-open the
 * active group on SPA navigation through the exposed open() method. */
function loadOpen(): string[] {
  try {
    const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]')
    return Array.isArray(raw) ? (raw as string[]) : []
  } catch {
    return []
  }
}
const persistedOpen = ref<string[]>(loadOpen())
const defaultOpeneds = computed(() => {
  const set = new Set(persistedOpen.value)
  if (activeGroupKey.value) set.add(activeGroupKey.value)
  return [...set]
})

function persistOpen() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(persistedOpen.value))
}
function onOpen(index: string) {
  if (!persistedOpen.value.includes(index)) {
    persistedOpen.value = [...persistedOpen.value, index]
    persistOpen()
  }
}
function onClose(index: string) {
  persistedOpen.value = persistedOpen.value.filter((k) => k !== index)
  persistOpen()
}

const menuRef = ref<{ open: (i: string) => void } | null>(null)

// Persistent Inertia layout is not remounted between visits, so default-openeds
// (initial-only) can't auto-expand later navigations — do it imperatively.
watch(activeGroupKey, (key) => {
  if (key) menuRef.value?.open(key)
})

function onSelect(index: string) {
  mobileNavOpen.value = false
  if (index && index !== currentPath.value) router.visit(index)
}
</script>

<template>
  <el-container class="pro-layout">
    <el-aside class="pro-aside" width="230px">
      <div class="pro-brand">
        <Link :href="adminRoutes.dashboard" class="pro-brand__link">Mcweb Admin</Link>
      </div>
      <el-scrollbar class="pro-nav-scroll">
        <el-menu
          ref="menuRef"
          :default-active="currentPath"
          :default-openeds="defaultOpeneds"
          class="pro-menu"
          @select="onSelect"
          @open="onOpen"
          @close="onClose"
        >
          <el-sub-menu v-for="group in nav" :key="group.key" :index="group.key">
            <template #title>
              <el-icon><component :is="group.icon" /></el-icon>
              <span>{{ group.label }}</span>
            </template>
            <el-menu-item v-for="item in group.items" :key="item.href" :index="item.href">
              {{ item.label }}
            </el-menu-item>
          </el-sub-menu>
        </el-menu>
      </el-scrollbar>
      <div class="pro-aside__footer">
        <span v-if="auth.user" class="pro-aside__user">{{ auth.user.username }}</span>
        <span v-if="auth.user" class="pro-aside__sep"> · </span>
        <Link :href="adminRoutes.site" class="pro-aside__site">{{ t('common.backToSite') }}</Link>
      </div>
    </el-aside>

    <el-container class="pro-body">
      <el-header class="pro-header">
        <div class="pro-header__left">
          <el-button
            class="pro-header__menu-btn"
            :icon="Expand"
            text
            :aria-label="t('common.openMenu')"
            @click="mobileNavOpen = true"
          />
          <el-breadcrumb separator="/" class="pro-crumbs">
            <el-breadcrumb-item>
              <Link :href="adminRoutes.dashboard" class="pro-crumb-root">{{ t('common.adminPanel') }}</Link>
            </el-breadcrumb-item>
            <el-breadcrumb-item v-for="crumb in trailingCrumbs" :key="crumb.label">
              {{ crumb.label }}
            </el-breadcrumb-item>
          </el-breadcrumb>
        </div>
        <div class="pro-header__right">
          <LanguageSwitcher />
          <el-button
            circle
            :icon="isDark ? Sunny : Moon"
            :title="t('common.toggleTheme')"
            :aria-label="t('common.toggleTheme')"
            @click="toggleTheme"
          />
        </div>
      </el-header>

      <el-main class="pro-main">
        <div class="pro-main__inner">
          <FlashMessages />
          <slot />
        </div>
      </el-main>
    </el-container>
  </el-container>

  <!-- Mobile navigation: same menu inside an el-drawer. destroy-on-close resets
       the menu each open so default-openeds re-expands the active group. -->
  <el-drawer
    v-model="mobileNavOpen"
    direction="ltr"
    size="260px"
    :with-header="false"
    destroy-on-close
    class="pro-drawer"
  >
    <div class="pro-brand">
      <Link :href="adminRoutes.dashboard" class="pro-brand__link" @click="mobileNavOpen = false">
        Mcweb Admin
      </Link>
    </div>
    <el-scrollbar class="pro-nav-scroll">
      <el-menu
        :default-active="currentPath"
        :default-openeds="defaultOpeneds"
        class="pro-menu"
        @select="onSelect"
      >
        <el-sub-menu v-for="group in nav" :key="`m-${group.key}`" :index="group.key">
          <template #title>
            <el-icon><component :is="group.icon" /></el-icon>
            <span>{{ group.label }}</span>
          </template>
          <el-menu-item v-for="item in group.items" :key="`m-${item.href}`" :index="item.href">
            {{ item.label }}
          </el-menu-item>
        </el-sub-menu>
      </el-menu>
    </el-scrollbar>
    <div class="pro-aside__footer">
      <span v-if="auth.user" class="pro-aside__user">{{ auth.user.username }}</span>
      <span v-if="auth.user" class="pro-aside__sep"> · </span>
      <Link :href="adminRoutes.site" class="pro-aside__site" @click="mobileNavOpen = false">
        {{ t('common.backToSite') }}
      </Link>
    </div>
  </el-drawer>
</template>

<style scoped>
.pro-layout {
  min-height: 100dvh;
  background: var(--el-bg-color-page);
}

.pro-aside {
  display: flex;
  flex-direction: column;
  height: 100dvh;
  position: sticky;
  top: 0;
  border-right: 1px solid var(--el-border-color-light);
  background: var(--el-bg-color);
}

.pro-brand {
  display: flex;
  align-items: center;
  height: 56px;
  padding: 0 20px;
  border-bottom: 1px solid var(--el-border-color-light);
}
.pro-brand__link {
  font-size: 15px;
  font-weight: 600;
  color: var(--el-text-color-primary);
  text-decoration: none;
}

.pro-nav-scroll {
  flex: 1;
  min-height: 0;
}
.pro-menu {
  border-right: none;
  padding: 6px 8px;
  --el-menu-item-height: 44px;
  --el-menu-sub-item-height: 44px;
}
/* Round + space each row so an expanded group reads as a list, not a dense wall. */
.pro-menu :deep(.el-sub-menu__title),
.pro-menu :deep(.el-menu-item) {
  border-radius: 8px;
}
.pro-menu :deep(.el-sub-menu__title) {
  margin-bottom: 2px;
}
.pro-menu :deep(.el-menu-item) {
  margin: 2px 0;
  min-width: 0;
}
/* Give child items extra indent so the hierarchy is legible at a glance. */
.pro-menu :deep(.el-sub-menu .el-menu-item) {
  padding-left: 52px !important;
}

.pro-aside__footer {
  border-top: 1px solid var(--el-border-color-light);
  padding: 12px 20px;
  font-size: 12px;
  color: var(--el-text-color-secondary);
}
.pro-aside__site {
  color: var(--el-text-color-secondary);
  text-decoration: none;
}
.pro-aside__site:hover {
  color: var(--el-color-primary);
}

.pro-body {
  min-width: 0;
}

.pro-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 56px;
  padding: 0 16px;
  border-bottom: 1px solid var(--el-border-color-light);
  background: var(--el-bg-color);
}
.pro-header__left,
.pro-header__right {
  display: flex;
  align-items: center;
  gap: 8px;
}
.pro-header__menu-btn {
  display: none;
}

.pro-main {
  padding: 24px;
}
.pro-main__inner {
  width: 100%;
  max-width: 1152px;
  margin: 0 auto;
}

.pro-crumb-root {
  color: var(--el-text-color-regular);
  text-decoration: none;
}
.pro-crumb-root:hover {
  color: var(--el-color-primary);
}

@media (max-width: 768px) {
  .pro-aside {
    display: none;
  }
  .pro-header__menu-btn {
    display: inline-flex;
  }
  .pro-main {
    padding: 16px;
  }
}
</style>
