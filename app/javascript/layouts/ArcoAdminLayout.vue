<script setup lang="ts">
/**
 * ArcoAdminLayout — Arco Design shell for McWeb admin (sidebar + navbar + content).
 * Inspired by Arco Pro default-layout; navigation uses Inertia router.visit(), not vue-router.
 */
import { computed, ref, watch, type Component } from 'vue'
import { Link, router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  IconCloud,
  IconCommand,
  IconDashboard,
  IconGift,
  IconHome,
  IconMenuFold,
  IconMenuUnfold,
  IconMessage,
  IconMoon,
  IconSettings,
  IconSun,
  IconUserGroup,
} from '@arco-design/web-vue/es/icon'
import AdminFlashMessages from '@/components/admin/AdminFlashMessages.vue'
import AdminLanguageSwitcher from '@/components/admin/AdminLanguageSwitcher.vue'
import DeveloperModeTools from '@/components/admin/DeveloperModeTools.vue'
import PluginUiSlots from '@/components/plugins/PluginUiSlots.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { useTheme } from '@/lib/useTheme'

interface NavItem {
  label: string
  href: string
  moduleKey?: string
  permissionKey?: string
  permissionAny?: string[]
  capabilityKey?: string
}
interface NavGroup {
  key: string
  label: string
  items: NavItem[]
  icon: Component
  moduleKey?: string
}

const page = usePage()
const { t } = useI18n()
const auth = computed(
  () => (page.props.auth ?? { user: null }) as {
    user: {
      username: string
      admin_modules?: string[]
      admin_permissions?: string[]
      admin_capabilities?: Record<string, boolean>
    } | null
  },
)
const { isDark, toggleTheme } = useTheme()
const adminDemoEnabled = computed(() => page.props.admin_demo_enabled === true)
const developerMode = computed(
  () =>
    (page.props.developer_mode ?? { enabled: false }) as {
      enabled: boolean
      profile?: string
      production_environment?: boolean
      workbench_access?: boolean
    },
)
const developerModeMessage = computed(() =>
  [
    t('common.developerModeWarning'),
    developerMode.value.production_environment
      ? t('common.developerModeProductionWarning')
      : null,
  ].filter(Boolean).join(' '),
)

const STORAGE_KEY = 'mc-admin-arco-nav-open'
const collapsed = ref(false)
const mobileNavOpen = ref(false)

const grantedAdminModules = computed(
  () => new Set(auth.value.user?.admin_modules || []),
)
const grantedAdminPermissions = computed(
  () => new Set(auth.value.user?.admin_permissions || []),
)

function hasAdminModule(moduleKey: string) {
  return grantedAdminModules.value.has(moduleKey)
}

function hasAdminPermission(permissionKey: string) {
  return grantedAdminPermissions.value.has(permissionKey)
}

function hasAnyAdminPermission(permissionKeys: string[]) {
  return permissionKeys.some((permissionKey) => hasAdminPermission(permissionKey))
}

function hasAdminCapability(capabilityKey: string) {
  return auth.value.user?.admin_capabilities?.[capabilityKey] === true
}

const nav = computed<NavGroup[]>(() => {
  const groups: NavGroup[] = [
    {
      key: 'overview',
      label: t('admin.overview'),
      icon: IconDashboard,
      items: [
        { label: t('admin.dashboard.title'), href: adminRoutes.dashboard },
        {
          label: t('admin.users'),
          href: adminRoutes.users,
          moduleKey: 'system',
          permissionKey: 'system.settings.manage',
        },
        {
          label: t('admin.roles'),
          href: adminRoutes.roles,
          moduleKey: 'system',
          permissionKey: 'identity.roles.read',
        },
        ...(adminDemoEnabled.value
          ? [{ label: t('admin.arcoDemo'), href: adminRoutes.arcoDemo }]
          : []),
      ],
    },
    {
      key: 'identity',
      label: t('admin.identity'),
      icon: IconUserGroup,
      moduleKey: 'identity',
      items: [
        {
          label: t('admin.forumUserGroups'),
          href: adminRoutes.forumUserGroups,
          permissionKey: 'identity.groups.read',
        },
      ],
    },
    {
      key: 'website',
      label: t('admin.website.title'),
      icon: IconHome,
      moduleKey: 'website',
      items: [
        {
          label: t('admin.pages'),
          href: adminRoutes.websitePages,
          permissionKey: 'website.pages.read',
        },
        {
          label: t('admin.articles'),
          href: adminRoutes.websiteArticles,
          permissionKey: 'website.articles.read',
        },
        {
          label: t('admin.website.nav.title', 'Navigation'),
          href: adminRoutes.websiteNavItems,
          permissionKey: 'website.pages.read',
        },
        {
          label: t('admin.website.themes.title', 'Themes'),
          href: adminRoutes.websiteThemes,
          permissionKey: 'website.pages.read',
        },
        {
          label: t('admin.frontendTemplates'),
          href: adminRoutes.frontendTemplates,
          permissionKey: 'website.templates.manage',
        },
      ],
    },
    {
      key: 'community',
      label: t('admin.community'),
      icon: IconMessage,
      moduleKey: 'forum',
      items: [
        { label: t('admin.forumStats'), href: adminRoutes.forumStats },
        {
          label: t('admin.forumSections'),
          href: adminRoutes.forumSections,
          permissionAny: [
            'forum.sections.manage',
            'forum.sections.lifecycle',
            'forum.sections.delete',
          ],
        },
        {
          label: t('admin.forumCategories'),
          href: adminRoutes.forumCategories,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumTopics'),
          href: adminRoutes.forumTopics,
          permissionKey: 'forum.topics.lock',
        },
        {
          label: t('admin.forumReports'),
          href: adminRoutes.forumReports,
          permissionKey: 'forum.topics.lock',
        },
        {
          label: t('admin.forumApprovals'),
          href: adminRoutes.forumApprovals,
          capabilityKey: 'forum.approvals.read',
        },
        {
          label: t('admin.forumModerationWorkbench'),
          href: adminRoutes.forumModerationWorkbench,
          capabilityKey: 'forum.moderation_workbench.read',
        },
        {
          label: t('admin.forumUserFields'),
          href: adminRoutes.forumUserFields,
          permissionKey: 'forum.topics.lock',
        },
        {
          label: t('admin.forumTopicFields'),
          href: adminRoutes.forumTopicFields,
          permissionKey: 'forum.topics.lock',
        },
        {
          label: t('admin.forumBadges'),
          href: adminRoutes.forumBadges,
          permissionKey: 'forum.badges.manage',
        },
        {
          label: t('admin.forumPoints'),
          href: adminRoutes.forumPoints,
          permissionKey: 'forum.points.manage',
        },
        {
          label: t('admin.forumWarningTemplates'),
          href: adminRoutes.forumWarningTemplates,
          permissionKey: 'forum.users.warn',
        },
        {
          label: t('admin.forumUserTitles'),
          href: adminRoutes.forumUserTitles,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumNotices'),
          href: adminRoutes.forumNotices,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumHelpArticles'),
          href: adminRoutes.forumHelpArticles,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumSmilies'),
          href: adminRoutes.forumSmilies,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumReactionTypes'),
          href: adminRoutes.forumReactionTypes,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumCustomBbcodes'),
          href: adminRoutes.forumCustomBbcodes,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumThemes'),
          href: adminRoutes.forumThemes,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumPages'),
          href: adminRoutes.forumPages,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumPhrases'),
          href: adminRoutes.forumPhrases,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumAttachments'),
          href: adminRoutes.forumAttachments,
          permissionKey: 'forum.attachments.security.read',
        },
        {
          label: t('admin.forumScheduledTasks'),
          href: adminRoutes.forumScheduledTasks,
          permissionKey: 'forum.sections.manage',
        },
        {
          label: t('admin.forumTags'),
          href: adminRoutes.forumTags,
          permissionKey: 'forum.tags.manage',
        },
        {
          label: t('admin.forumSettings.title'),
          href: adminRoutes.forumSettings,
          moduleKey: 'system',
          permissionKey: 'system.settings.manage',
        },
        {
          label: t('admin.forumWebhookDeliveries'),
          href: adminRoutes.forumWebhookDeliveries,
          moduleKey: 'system',
          permissionKey: 'system.settings.manage',
        },
        {
          label: t('admin.forumEventWebhookDeliveries'),
          href: adminRoutes.forumEventWebhookDeliveries,
          moduleKey: 'system',
          permissionKey: 'system.settings.manage',
        },
      ],
    },
    {
      key: 'store',
      label: t('admin.store'),
      icon: IconGift,
      moduleKey: 'store',
      items: [
        {
          label: t('admin.storeProducts'),
          href: adminRoutes.storeProducts,
          permissionKey: 'store.products.manage',
        },
        {
          label: t('admin.storeInventory'),
          href: adminRoutes.storeInventory,
          permissionKey: 'store.inventory.read',
        },
        {
          label: t('admin.storeFinance'),
          href: adminRoutes.storeFinance,
          permissionKey: 'store.finance.read',
        },
        {
          label: t('admin.storeCategories'),
          href: adminRoutes.storeCategories,
          permissionKey: 'store.products.manage',
        },
        {
          label: t('admin.storeCoupons'),
          href: adminRoutes.storeCoupons,
          permissionKey: 'store.products.manage',
        },
        {
          label: t('admin.storeMembershipTypes'),
          href: adminRoutes.storeMembershipTypes,
          permissionKey: 'store.products.manage',
        },
        {
          label: t('admin.storeUserMemberships'),
          href: adminRoutes.storeUserMemberships,
          permissionKey: 'store.entitlements.read',
        },
        {
          label: t('admin.storeUserEntitlements'),
          href: adminRoutes.storeUserEntitlements,
          permissionKey: 'store.entitlements.read',
        },
        {
          label: t('admin.storeGiftCards'),
          href: adminRoutes.storeGiftCards,
          permissionKey: 'store.products.manage',
        },
        {
          label: t('admin.storeCreditUsers'),
          href: adminRoutes.storeCreditUsers,
          permissionKey: 'store.credit.read',
        },
        {
          label: t('admin.storeOrders'),
          href: adminRoutes.storeOrders,
          permissionKey: 'store.orders.read',
        },
        {
          label: t('admin.storePaymentProviders'),
          href: adminRoutes.storePaymentProviders,
          permissionKey: 'store.payments.configure',
        },
        {
          label: t('admin.storePaymentOperations'),
          href: adminRoutes.storePaymentOperations,
          permissionKey: 'store.orders.read',
        },
        {
          label: t('admin.storeDisputes'),
          href: adminRoutes.storeDisputes,
          permissionKey: 'store.disputes.read',
        },
        {
          label: t('admin.storeLatePaymentCases'),
          href: adminRoutes.storeLatePaymentCases,
          permissionKey: 'store.payments.late_review',
        },
        {
          label: t('admin.storePaymentReconciliations'),
          href: adminRoutes.storePaymentReconciliations,
          permissionKey: 'store.payments.reconciliation.read',
        },
        {
          label: t('admin.storeWebhookDeliveries'),
          href: adminRoutes.storeWebhookDeliveries,
          moduleKey: 'system',
          permissionKey: 'system.settings.manage',
        },
        {
          label: t('admin.storeReviews'),
          href: adminRoutes.storeReviews,
          permissionKey: 'store.products.manage',
        },
        {
          label: t('admin.storeProductQuestions'),
          href: adminRoutes.storeProductQuestions,
          permissionKey: 'store.questions.manage',
        },
        {
          label: t('admin.storeFulfillments'),
          href: adminRoutes.storeFulfillments,
          permissionKey: 'store.fulfillments.read',
        },
        {
          label: t('admin.storeSettings.title'),
          href: adminRoutes.storeSettings,
          moduleKey: 'system',
          permissionKey: 'system.settings.manage',
        },
      ],
    },
    {
      key: 'minecraft',
      label: t('admin.minecraft'),
      icon: IconCloud,
      moduleKey: 'minecraft',
      items: [
        {
          label: t('admin.minecraftServers'),
          href: adminRoutes.minecraftServers,
          permissionKey: 'minecraft.servers.manage',
        },
        {
          label: t('admin.minecraftNodes'),
          href: adminRoutes.minecraftNodes,
          permissionKey: 'minecraft.nodes.manage',
        },
        {
          label: t('admin.minecraftPlayers'),
          href: adminRoutes.minecraftPlayers,
          permissionAny: [
            'minecraft.players.view',
            'minecraft.primary_accounts.review',
            'minecraft.primary_accounts.switch_for_user',
          ],
        },
        {
          label: t('admin.minecraftSettings'),
          href: adminRoutes.minecraftSettings,
          permissionKey: 'minecraft.servers.manage',
        },
        {
          label: t('admin.minecraftIntegrationActions'),
          href: adminRoutes.minecraftIntegrationActions,
          permissionKey: 'minecraft.servers.manage',
        },
        {
          label: t('admin.minecraftProfileFields'),
          href: adminRoutes.minecraftProfileFields,
          permissionKey: 'minecraft.servers.manage',
        },
        {
          label: t('admin.minecraftPermissionMappings'),
          href: adminRoutes.minecraftPermissionMappings,
          permissionKey: 'minecraft.servers.manage',
        },
      ],
    },
    {
      key: 'system',
      label: t('admin.system'),
      icon: IconSettings,
      moduleKey: 'system',
      items: [
        {
          label: t('admin.auditLogs'),
          href: adminRoutes.auditLogs,
          permissionKey: 'system.audit.read',
        },
        {
          label: t('admin.dataGovernance.nav'),
          href: adminRoutes.dataGovernance,
          permissionKey: 'data_governance.read',
        },
        {
          label: t('admin.ipBans'),
          href: adminRoutes.ipBans,
          permissionKey: 'system.bans.manage',
        },
        {
          label: t('admin.emailBans'),
          href: adminRoutes.emailBans,
          permissionKey: 'system.bans.manage',
        },
        {
          label: t('admin.systemApiKeys'),
          href: adminRoutes.systemApiKeys,
          permissionKey: 'system.settings.manage',
        },
        {
          label: t('admin.systemWebhookSubscriptions'),
          href: adminRoutes.systemWebhookSubscriptions,
          permissionKey: 'system.settings.manage',
        },
        {
          label: t('admin.featureToggles.title'),
          href: adminRoutes.featureToggles,
          permissionKey: 'system.settings.manage',
        },
        {
          label: t('admin.rateLimits.title'),
          href: adminRoutes.rateLimits,
          permissionKey: 'system.settings.manage',
        },
        {
          label: t('admin.applications.nav'),
          href: adminRoutes.applications,
          permissionAny: [ 'system.settings.manage', 'system.plugins.manage' ],
        },
        {
          label: t('admin.pluginSettings.nav'),
          href: adminRoutes.pluginSettings,
          permissionKey: 'system.plugins.settings.manage',
        },
        {
          label: t('admin.settings'),
          href: adminRoutes.settings,
          permissionKey: 'system.settings.manage',
        },
        ...(developerMode.value.workbench_access
          ? [{
              label: t('admin.developerWorkbench.nav'),
              href: adminRoutes.developerWorkbench,
              permissionKey: 'system.settings.manage',
            }]
          : []),
        {
          label: t('admin.jobs'),
          href: adminRoutes.jobs,
          permissionKey: 'system.jobs.read',
        },
      ],
    },
  ]

  const pluginItems =
    (
      page.props.plugin_contributions as
        | { navigation?: { admin?: Array<{ label: string; href: string }> } }
        | undefined
    )?.navigation?.admin || []
  if (pluginItems.length > 0) {
    groups.push({
      key: 'plugin-contributions',
      label: t('admin.pluginPages.navGroup'),
      icon: IconGift,
      items: pluginItems.map((item) => ({
        label: item.label,
        href: item.href,
      })),
    })
  }

  return groups
    .map((group) => ({
      ...group,
      items: group.items.filter(
        (item) => {
          const requiredModuleKey = item.moduleKey ?? group.moduleKey
          return (
            (!requiredModuleKey || hasAdminModule(requiredModuleKey))
            && (!item.permissionKey || hasAdminPermission(item.permissionKey))
            && (!item.permissionAny || hasAnyAdminPermission(item.permissionAny))
            && (!item.capabilityKey || hasAdminCapability(item.capabilityKey))
          )
        },
      ),
    }))
    .filter((group) => group.items.length > 0)
})

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
  if (!key || key === currentPath.value) return

  router.visit(key)
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

  <a-layout class="arco-admin-layout">
    <a-layout-sider
      class="arco-admin-sider"
      :collapsed="collapsed"
      :width="220"
      :collapsed-width="48"
      collapsible
      :hide-trigger="true"
    >
      <div class="arco-admin-brand">
        <Link :href="adminRoutes.dashboard" class="arco-admin-brand__link">
          <icon-command class="arco-admin-brand__icon" />
          <span v-show="!collapsed" class="arco-admin-brand__text">
            {{ t('common.adminBrand') }}
          </span>
        </Link>
      </div>
      <div class="arco-admin-sider__menu">
        <a-menu
          :selected-keys="activeItemHref ? [activeItemHref] : []"
          v-model:open-keys="openKeys"
          :collapsed="collapsed"
          @menu-item-click="onMenuClick"
        >
          <a-sub-menu
            v-for="group in nav"
            :key="group.key"
            :class="`arco-admin-nav-group arco-admin-nav-group--${group.key}`"
          >
            <template #icon><component :is="group.icon" /></template>
            <template #title>{{ group.label }}</template>
            <a-menu-item
              v-for="item in group.items"
              :key="item.href"
              :data-prefetch-href="item.href"
            >
              {{ item.label }}
            </a-menu-item>
          </a-sub-menu>
        </a-menu>
      </div>
      <div v-show="!collapsed" class="arco-admin-sider__footer">
        <span v-if="auth.user">{{ auth.user.username }}</span>
        <span v-if="auth.user"> · </span>
        <a :href="adminRoutes.site" data-admin-hard-navigation>{{ t('common.backToSite') }}</a>
      </div>
    </a-layout-sider>

    <a-layout class="arco-admin-body">
      <a-layout-header class="arco-admin-header">
        <div class="arco-admin-header__left">
          <a-button
            class="arco-admin-mobile-menu-trigger"
            type="text"
            :aria-label="t('common.openMenu')"
            @click="mobileNavOpen = true"
          >
            <template #icon><icon-menu-unfold /></template>
          </a-button>
          <a-button
            class="arco-admin-collapse-trigger"
            type="text"
            :aria-label="collapsed ? t('common.openMenu') : t('common.close')"
            @click="collapsed = !collapsed"
          >
            <template #icon>
              <icon-menu-unfold v-if="collapsed" />
              <icon-menu-fold v-else />
            </template>
          </a-button>
          <a-breadcrumb class="arco-admin-breadcrumb">
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

      <a-alert
        v-if="developerMode.enabled"
        class="arco-admin-developer-alert"
        type="warning"
        :title="t('common.developerMode')"
        data-testid="developer-mode-banner"
        role="alert"
        show-icon
        banner
      >
        {{ developerModeMessage }}
      </a-alert>

      <a-layout-content id="admin-content" class="arco-admin-main" tabindex="-1">
        <div class="arco-admin-main__inner">
          <AdminFlashMessages />
          <PluginUiSlots />
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
    <div class="arco-admin-drawer">
      <div class="arco-admin-brand arco-admin-brand--drawer">
        <Link :href="adminRoutes.dashboard" class="arco-admin-brand__link" @click="mobileNavOpen = false">
          <icon-command class="arco-admin-brand__icon" />
          <span class="arco-admin-brand__text">McWeb Admin</span>
        </Link>
      </div>
      <div class="arco-admin-drawer__menu">
        <a-menu
          :selected-keys="activeItemHref ? [activeItemHref] : []"
          v-model:open-keys="openKeys"
          @menu-item-click="onMenuClick"
        >
          <a-sub-menu
            v-for="group in nav"
            :key="group.key"
            :class="`arco-admin-nav-group arco-admin-nav-group--${group.key}`"
          >
            <template #icon><component :is="group.icon" /></template>
            <template #title>{{ group.label }}</template>
            <a-menu-item
              v-for="item in group.items"
              :key="item.href"
              :data-prefetch-href="item.href"
            >
              {{ item.label }}
            </a-menu-item>
          </a-sub-menu>
        </a-menu>
      </div>
      <div class="arco-admin-sider__footer">
        <span v-if="auth.user">{{ auth.user.username }}</span>
        <span v-if="auth.user"> · </span>
        <a
          :href="adminRoutes.site"
          data-admin-hard-navigation
          @click="mobileNavOpen = false"
        >
          {{ t('common.backToSite') }}
        </a>
      </div>
    </div>
  </a-drawer>

  <DeveloperModeTools />
</template>

<style scoped>
.arco-admin-layout {
  height: 100dvh;
  min-height: 100dvh;
  overflow: hidden;
  background: var(--mc-admin-canvas, var(--color-bg-1));
}

.arco-admin-body {
  min-width: 0;
  min-height: 0;
  height: 100%;
  max-width: 100%;
  overflow: hidden;
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
  border-radius: var(--mc-admin-radius-control, 7px);
  box-shadow: var(--mc-admin-shadow-md);
  transform: translateY(-150%);
}
.arco-admin-skip-link:focus {
  transform: translateY(0);
}

.arco-admin-sider {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  flex: 0 0 auto;
  overflow: hidden;
  border-right: 1px solid var(--mc-admin-border, var(--color-border-2));
  background:
    linear-gradient(180deg, rgba(var(--primary-6), 0.05), transparent 180px),
    var(--mc-admin-surface-raised, var(--color-bg-2));
}
.arco-admin-sider :deep(.arco-layout-sider-children) {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
}

.arco-admin-brand {
  flex: 0 0 60px;
  display: flex;
  align-items: center;
  height: 60px;
  min-width: 0;
  padding: 0 16px;
  border-bottom: 1px solid var(--mc-admin-border, var(--color-border-2));
}
.arco-admin-brand--drawer {
  flex-basis: 60px;
}
.arco-admin-sider.arco-layout-sider-collapsed .arco-admin-brand {
  padding-inline: 7px;
}
.arco-admin-brand__link {
  min-width: 0;
  display: inline-flex;
  align-items: center;
  gap: 10px;
  color: var(--color-text-1);
  text-decoration: none;
  font-weight: 600;
  font-size: 15px;
}
.arco-admin-brand__icon {
  flex: 0 0 auto;
  width: 34px;
  height: 34px;
  padding: 7px;
  border-radius: 10px;
  font-size: 20px;
  color: #fff;
  background: linear-gradient(145deg, rgb(var(--primary-6)), #7048e8);
  box-shadow: 0 6px 16px rgba(var(--primary-6), 0.24);
}
.arco-admin-brand__text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.arco-admin-sider__menu {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 8px;
}
.arco-admin-sider__menu :deep(.arco-menu-inner) {
  overflow: visible;
  padding: 0;
  background: transparent;
}
.arco-admin-sider.arco-layout-sider-collapsed .arco-admin-sider__menu {
  padding-inline: 4px;
}
.arco-admin-sider__menu :deep(.arco-menu-item),
.arco-admin-sider__menu :deep(.arco-menu-inline-header) {
  margin-block: 2px;
  border-radius: 8px;
}
.arco-admin-sider__menu :deep(.arco-menu-selected) {
  color: rgb(var(--primary-6));
  background: linear-gradient(90deg, rgba(var(--primary-6), 0.14), rgba(var(--primary-6), 0.05));
  font-weight: 600;
}
.arco-admin-sider__menu :deep(.arco-admin-nav-group > .arco-menu-inline-header .arco-menu-icon) {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 26px;
  height: 26px;
  margin-right: 8px;
  color: rgb(var(--primary-6));
  border-radius: 50%;
  background: rgba(var(--primary-6), 0.09);
}
.arco-admin-sider__menu :deep(.arco-admin-nav-group--community > .arco-menu-inline-header .arco-menu-icon) {
  color: rgb(var(--purple-6));
  background: rgb(var(--purple-1));
}
.arco-admin-sider__menu :deep(.arco-admin-nav-group--store > .arco-menu-inline-header .arco-menu-icon) {
  color: rgb(var(--orangered-6));
  background: rgb(var(--orangered-1));
}
.arco-admin-sider__menu :deep(.arco-admin-nav-group--minecraft > .arco-menu-inline-header .arco-menu-icon) {
  color: rgb(var(--green-6));
  background: rgb(var(--green-1));
}
.arco-admin-sider__menu :deep(.arco-admin-nav-group--system > .arco-menu-inline-header .arco-menu-icon) {
  color: rgb(var(--gray-8));
  background: var(--color-fill-3);
}
.arco-admin-sider.arco-layout-sider-collapsed
  .arco-admin-sider__menu
  :deep(.arco-admin-nav-group > .arco-menu-inline-header .arco-menu-icon) {
  margin-right: 0;
}

.arco-admin-sider__footer {
  flex: 0 0 auto;
  min-width: 0;
  padding: 12px 16px;
  font-size: 12px;
  color: var(--color-text-2);
  margin: 0 8px 8px;
  border: 1px solid var(--mc-admin-border, var(--color-border-2));
  border-radius: 8px;
  background: var(--mc-admin-surface-muted, var(--color-fill-1));
}
.arco-admin-sider__footer a {
  color: var(--color-text-2);
  text-decoration: none;
}
.arco-admin-sider__footer a:hover {
  color: rgb(var(--primary-6));
}

.arco-admin-header {
  flex: 0 0 60px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 60px;
  min-width: 0;
  padding: 0 20px;
  gap: 12px;
  background: var(--mc-admin-surface, var(--color-bg-2));
  border-bottom: 1px solid var(--mc-admin-border, var(--color-border-2));
  box-shadow: 0 2px 12px rgb(23 43 77 / 5%);
  backdrop-filter: blur(14px);
}
.arco-admin-header__left {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
}
.arco-admin-header__right {
  flex: 0 0 auto;
  min-width: max-content;
}
.arco-admin-header__left,
.arco-admin-header__right {
  display: flex;
  align-items: center;
  gap: 8px;
}
.arco-admin-header :deep(.arco-btn) {
  flex: 0 0 auto;
  border-radius: 8px;
}
.arco-admin-header :deep(.arco-btn:hover) {
  color: rgb(var(--primary-6));
  background: rgba(var(--primary-6), 0.09);
}

.arco-admin-breadcrumb {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
}
.arco-admin-breadcrumb :deep(.arco-breadcrumb-item-label) {
  display: inline-block;
  max-width: clamp(72px, 14vw, 220px);
  overflow: hidden;
  text-overflow: ellipsis;
  vertical-align: middle;
  white-space: nowrap;
}

.arco-admin-developer-alert {
  flex: 0 0 auto;
  width: auto;
  min-width: 0;
  max-width: calc(100% - 32px);
  margin: 10px 16px 0;
  border-radius: 9px;
}
.arco-admin-developer-alert :deep(.arco-alert-body),
.arco-admin-developer-alert :deep(.arco-alert-content) {
  min-width: 0;
}
.arco-admin-developer-alert :deep(.arco-alert-description) {
  overflow-wrap: anywhere;
}

.arco-admin-mobile-menu-trigger {
  display: none;
}

.arco-admin-collapse-trigger {
  display: inline-flex;
}

.arco-admin-main {
  flex: 1 1 auto;
  min-width: 0;
  min-height: 0;
  padding: 24px;
  overflow: auto;
  overscroll-behavior: contain;
}
.arco-admin-main__inner {
  width: 100%;
  min-width: 0;
  max-width: 1440px;
  margin: 0 auto;
}

.arco-admin-drawer {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
}
.arco-admin-drawer__menu {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
}
.arco-admin-drawer__menu :deep(.arco-menu-inner) {
  overflow: visible;
}

@media (max-width: 1279px) {
  .arco-admin-header {
    padding-inline: 16px;
  }

  .arco-admin-main {
    padding: 20px;
  }
}

@media (max-width: 1099px) {
  .arco-admin-sider {
    display: none !important;
  }

  .arco-admin-mobile-menu-trigger {
    display: inline-flex !important;
  }

  .arco-admin-collapse-trigger {
    display: none !important;
  }

  .arco-admin-main :deep(.arco-page-header),
  .arco-admin-main :deep(.arco-page-header-wrapper),
  .arco-admin-main :deep(.arco-page-header-header),
  .arco-admin-main :deep(.arco-page-header-main),
  .arco-admin-main :deep(.arco-page-header-extra) {
    width: 100%;
    min-width: 0;
  }

  .arco-admin-main :deep(.arco-page-header) {
    box-sizing: border-box;
    max-width: 100%;
    padding: 14px !important;
  }

  .arco-admin-main :deep(.arco-page-header-header) {
    flex-wrap: wrap;
    gap: 8px;
    padding-inline: 0;
  }

  .arco-admin-main :deep(.arco-page-header-main) {
    flex: 1 1 100%;
    flex-direction: column;
    align-items: flex-start;
  }

  .arco-admin-main :deep(.arco-page-header-divider) {
    display: none;
  }

  .arco-admin-main :deep(.arco-page-header-subtitle) {
    width: 100%;
    margin-top: 4px;
    overflow: visible;
    line-height: 20px;
    white-space: normal;
  }

  .arco-admin-main :deep(.arco-page-header-extra) {
    flex: 1 1 100%;
    white-space: normal;
  }
}

@media (max-width: 767px) {
  .arco-admin-main {
    padding: 16px;
    overflow-x: hidden;
  }

  .arco-admin-main :deep(.arco-table-content-scroll-x) {
    overflow-x: auto;
  }
}

@media (max-width: 479px) {
  .arco-admin-header {
    padding-inline: 12px;
    gap: 8px;
  }

  .arco-admin-header__left,
  .arco-admin-header__right {
    gap: 4px;
  }

  .arco-admin-breadcrumb :deep(.arco-breadcrumb-item-label) {
    max-width: 88px;
  }

  .arco-admin-main {
    padding: 12px;
  }
}

@media (min-width: 1100px) {
  .arco-admin-sider {
    display: flex !important;
  }

  .arco-admin-mobile-menu-trigger {
    display: none !important;
  }

  .arco-admin-collapse-trigger {
    display: inline-flex !important;
  }
}
</style>
