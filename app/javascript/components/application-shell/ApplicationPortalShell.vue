<script setup lang="ts">
// Shared by the independently booted Account, Forum, Store, and Staff applications.
import { computed, defineAsyncComponent, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Avatar,
  Badge,
  Button,
  Dropdown,
  Doption,
  Layout,
  LayoutContent,
  LayoutHeader,
  LayoutSider,
  Menu,
  MenuItem,
  Space,
  TypographyText,
} from '@mcweb/ui'
import {
  IconApps,
  IconCommand,
  IconHome,
  IconMenu,
  IconMessage,
  IconMoon,
  IconNotification,
  IconPoweroff,
  IconGift,
  IconQuestionCircle,
  IconSun,
  IconUser,
} from '@arco-design/web-vue/es/icon'

import LanguageSwitcher from '@/components/portal/LanguageSwitcher.vue'
import {
  isApplicationShellNavigationItemVisible,
  useApplicationShell,
  type ApplicationShellNavigationItem,
} from '@/lib/applicationShell'
import { usePortalApplicationStatusSurfaces } from '@/lib/applicationStatusSurfaces'
import { routes } from '@/lib/routes'
import { safeSignOut } from '@/lib/safeSignOut'
import { useTheme } from '@/lib/useTheme'
import { vAccessibleFormControlNames } from '@/directives/arcoAccessibility'

defineSlots<{
  default(): unknown
  'flash-messages'(): unknown
  'user-avatar'(props: {
    username: string
    imageUrl?: string | null
    size: number
  }): unknown
}>()

const page = usePage()
const DeveloperModeTools = __MCWEB_DEVELOPER_BUILD__
  ? defineAsyncComponent(() => import('@/components/portal/DeveloperModeTools.vue'))
  : null
const ApplicationPortalMobileNavigation = defineAsyncComponent(
  () => import('@/components/application-shell/ApplicationPortalMobileNavigation.vue'),
)
const { t } = useI18n()
const shell = useApplicationShell()
const {
  developerModeBanner,
  flashMessages,
  portalAnnouncements,
} = usePortalApplicationStatusSurfaces()
const { isDark, toggleTheme } = useTheme()
const mobileNavOpen = ref(false)
const signingOut = ref(false)
const compact = ref(false)
let compactQuery: MediaQueryList | null = null

const auth = computed(() => (
  page.props.auth ?? { user: null }
) as {
  user: { username: string; avatar_url?: string | null } | null
})
const notifications = computed(() => page.props.notifications as {
  unread_count: number
  url: string
} | undefined)
const notificationUnreadCount = computed(() => notifications.value?.unread_count ?? 0)
const messagesUnread = computed(() => page.props.messages_unread as {
  count: number
  url: string
} | undefined)
const cart = computed(() => page.props.cart as {
  count: number
  url: string
} | undefined)
const globalAnnouncements = computed(() => page.props.global_announcements as Array<{
  id: string
  title: string
  url: string
}> | undefined)
const forumNotices = computed(() => page.props.forum_notices as Array<{
  id: number
  title: string
  message_html: string
  style: string
  dismissible: boolean
  dismiss_url: string
}> | undefined)
const flash = computed(() => page.props.flash as {
  notice?: string
  alert?: string
} | undefined)
const hasFlashMessages = computed(() => Boolean(flash.value?.notice || flash.value?.alert))
const hasPortalAnnouncements = computed(() => (
  (globalAnnouncements.value?.length ?? 0) > 0 || (forumNotices.value?.length ?? 0) > 0
))
const developerMode = computed(() => (
  page.props.developer_mode ?? { enabled: false }
) as { enabled: boolean; production_environment?: boolean })
const developerModeMessage = computed(() => [
  t('common.developerModeWarning'),
  developerMode.value.production_environment
    ? t('common.developerModeProductionWarning')
    : null,
].filter(Boolean).join(' '))
const currentPath = computed(() => page.url.split('?')[0])
const visibleGroups = computed(() => shell.navigation
  .map((group) => ({
    ...group,
    items: group.items.filter((item) => isApplicationShellNavigationItemVisible(
      item,
      page.props,
      Boolean(auth.value.user),
    )),
  }))
  .filter((group) => group.items.length > 0))
const allItems = computed(() => visibleGroups.value.flatMap((group) => group.items))
const selectedKey = computed(() => allItems.value
  .filter((item) => currentPath.value === item.href || currentPath.value.startsWith(`${item.href}/`))
  .sort((left, right) => right.href.length - left.href.length)[0]?.href)
const mobileNavigationGroups = computed(() => visibleGroups.value.map((group) => ({
  id: group.id,
  label: t(group.labelKey),
  items: group.items.map((item) => ({
    href: item.href,
    label: t(item.labelKey),
    badge: navigationBadge(item),
  })),
})))

function navigationBadge(item: ApplicationShellNavigationItem): number {
  if (!item.badgeProp) return 0
  let value: unknown = page.props
  for (const segment of item.badgeProp.split('.')) {
    if (value === null || typeof value !== 'object') return 0
    value = (value as Record<string, unknown>)[segment]
  }
  return typeof value === 'number' && Number.isFinite(value) && value > 0
    ? Math.floor(value)
    : 0
}

function visit(path: string) {
  mobileNavOpen.value = false
  if (path === currentPath.value) return
  router.visit(path)
}

function syncCompact(event?: MediaQueryListEvent) {
  const nextCompact = event?.matches ?? compactQuery?.matches ?? false
  compact.value = nextCompact
  if (!nextCompact) mobileNavOpen.value = false
}

function syncArcoTheme() {
  document.body.toggleAttribute('arco-theme', isDark.value)
  if (isDark.value) document.body.setAttribute('arco-theme', 'dark')
}

function signOut() {
  if (signingOut.value) return
  signingOut.value = true
  void safeSignOut({
    onFinish: () => {
      signingOut.value = false
    },
  })
}

onMounted(() => {
  compactQuery = window.matchMedia('(max-width: 991px)')
  syncCompact()
  compactQuery.addEventListener('change', syncCompact)
})

onBeforeUnmount(() => compactQuery?.removeEventListener('change', syncCompact))
watch(isDark, syncArcoTheme, { immediate: true })
</script>

<template>
    <a href="#application-content" class="mc-shell-skip-link">
      {{ t('common.skipToContent') }}
    </a>
    <component
      :is="DeveloperModeTools"
      v-if="DeveloperModeTools && developerMode.enabled"
    />
    <Layout
      class="mc-shell-layout"
      data-mc-application-shell
      :data-mc-application="shell.applicationId"
      :style="{ minHeight: '100dvh' }"
    >
      <LayoutSider
        v-if="!compact"
        class="mc-shell-sidebar"
        data-mc-application-sidebar
        :width="248"
        :style="{
          position: 'fixed',
          inset: '0 auto 0 0',
          zIndex: 30,
          borderRight: '1px solid var(--color-border-2)',
          background: 'var(--color-bg-2)',
        }"
      >
        <Space
          align="center"
          :size="10"
          :style="{
            height: 'var(--mc-shell-topbar-height, 60px)',
            padding: '0 var(--mc-shell-header-padding-inline, 20px)',
          }"
        >
          <IconCommand :size="22" />
          <TypographyText bold>{{ t(shell.brandKey) }}</TypographyText>
        </Space>
        <template v-for="group in visibleGroups" :key="group.id">
          <TypographyText
            type="secondary"
            :style="{ display: 'block', padding: '14px 18px 6px', fontSize: '12px' }"
          >
            {{ t(group.labelKey) }}
          </TypographyText>
          <Menu
            data-mc-application-navigation
            :data-navigation-group="group.id"
            :selected-keys="selectedKey ? [selectedKey] : []"
            :style="{ borderRight: 0 }"
            @menu-item-click="visit"
          >
            <MenuItem v-for="item in group.items" :key="item.href">
              <span :style="{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px' }">
                <span>{{ t(item.labelKey) }}</span>
                <Badge
                  v-if="navigationBadge(item) > 0"
                  :count="navigationBadge(item)"
                  :max-count="99"
                />
              </span>
            </MenuItem>
          </Menu>
        </template>
      </LayoutSider>

      <Layout
        :style="{
          marginLeft: compact ? '0' : 'var(--mc-shell-sidebar-width, 248px)',
          width: compact ? '100%' : 'calc(100% - var(--mc-shell-sidebar-width, 248px))',
          minWidth: 0,
        }"
      >
        <LayoutHeader
          class="mc-shell-header"
          data-mc-application-header
          :style="{
            position: 'sticky',
            top: 0,
            zIndex: 20,
            height: 'var(--mc-shell-topbar-height, 60px)',
            minHeight: 'var(--mc-shell-topbar-height, 60px)',
            padding: '0 var(--mc-shell-header-padding-inline, 20px)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            borderBottom: '1px solid var(--color-border-2)',
            background: 'var(--color-bg-2)',
          }"
        >
          <Space align="center" :size="8">
            <Button
              v-if="compact"
              type="text"
              shape="circle"
              :aria-label="t('common.openMenu')"
              @click="mobileNavOpen = true"
            >
              <template #icon><IconMenu /></template>
            </Button>
            <TypographyText bold>{{ t(shell.brandKey) }}</TypographyText>
          </Space>

          <Space align="center" :size="4">
            <a :href="routes.home" :aria-label="t('common.backToSite')"><IconHome /></a>
            <a :href="routes.app" :aria-label="t('common.navigation')"><IconApps /></a>
            <Button
              type="text"
              shape="circle"
              href="/docs/"
              data-portal-hard-navigation
              :aria-label="t('common.documentation')"
            >
              <template #icon><IconQuestionCircle /></template>
            </Button>
            <LanguageSwitcher />
            <Button type="text" shape="circle" :aria-label="t('common.toggleTheme')" @click="toggleTheme">
              <template #icon><IconSun v-if="isDark" /><IconMoon v-else /></template>
            </Button>
            <Badge
              v-if="auth.user && notifications"
              :count="notificationUnreadCount"
              :max-count="99"
            >
              <Button
                type="text"
                shape="circle"
                :aria-label="t('common.notifications')"
                @click="visit(notifications.url)"
              >
                <template #icon><IconNotification /></template>
              </Button>
            </Badge>
            <Badge
              v-if="shell.applicationId === 'forum' && auth.user && messagesUnread"
              :count="messagesUnread.count"
              :max-count="99"
            >
              <Button
                type="text"
                shape="circle"
                :aria-label="t('common.messages')"
                @click="visit(messagesUnread.url)"
              >
                <template #icon><IconMessage /></template>
              </Button>
            </Badge>
            <Badge
              v-if="shell.applicationId === 'store' && cart"
              :count="cart.count"
              :max-count="99"
            >
              <Button
                type="text"
                shape="circle"
                :aria-label="t('common.cart')"
                @click="visit(cart.url)"
              >
                <template #icon><IconGift /></template>
              </Button>
            </Badge>
            <Dropdown v-if="auth.user" trigger="click" position="br">
              <Button
                type="text"
                shape="round"
                :aria-label="t('common.accountMenu', { username: auth.user.username })"
                data-mc-application-user-menu-trigger
              >
                <Space align="center" :size="8">
                  <slot
                    name="user-avatar"
                    :username="auth.user.username"
                    :image-url="auth.user.avatar_url"
                    :size="28"
                  >
                    <Avatar :size="28" :image-url="auth.user.avatar_url || undefined">
                      {{ auth.user.username.slice(0, 2).toUpperCase() }}
                    </Avatar>
                  </slot>
                  <TypographyText class="mc-shell-user-name">{{ auth.user.username }}</TypographyText>
                </Space>
              </Button>
              <template #content>
                <Doption disabled><IconUser /> {{ auth.user.username }}</Doption>
                <Doption @click="visit(routes.account)"><IconApps /> {{ t('common.personal') }}</Doption>
                <Doption :disabled="signingOut" @click="signOut">
                  <IconPoweroff /> {{ t('common.signOut') }}
                </Doption>
              </template>
            </Dropdown>
            <Button v-else type="primary" @click="visit(routes.signIn)">
              {{ t('common.signIn') }}
            </Button>
          </Space>
        </LayoutHeader>

        <component
          :is="developerModeBanner"
          v-if="developerMode.enabled && developerModeBanner"
          :title="t('common.developerMode')"
          :message="developerModeMessage"
        />

        <component
          :is="portalAnnouncements"
          v-if="shell.applicationId === 'forum' && hasPortalAnnouncements && portalAnnouncements"
          :authenticated="!!auth.user"
          :announcements="globalAnnouncements"
          :notices="forumNotices"
        />

        <LayoutContent
          id="application-content"
          class="mc-page-content mc-page-surface"
          data-mc-application-content
          tabindex="-1"
          :style="{
            padding: 'var(--mc-page-gutter, 24px)',
            minHeight: 'calc(100dvh - var(--mc-shell-topbar-height, 60px))',
          }"
        >
          <div
            v-accessible-form-control-names
            class="mc-page-container"
            :style="{ maxWidth: 'var(--mc-page-max-width, 1440px)', margin: '0 auto' }"
          >
            <slot name="flash-messages">
              <component
                :is="flashMessages"
                v-if="hasFlashMessages && flashMessages"
              />
            </slot>
            <slot />
          </div>
        </LayoutContent>
      </Layout>
    </Layout>

    <ApplicationPortalMobileNavigation
      v-if="mobileNavOpen"
      v-model:visible="mobileNavOpen"
      :brand-label="t(shell.brandKey)"
      :groups="mobileNavigationGroups"
      :selected-key="selectedKey"
      @select="visit"
    />

    <component :is="shell.accessory" v-if="shell.accessory" />
</template>
