<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Avatar,
  Badge,
  Button,
  ConfigProvider,
  Drawer,
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
  IconShoppingCart,
  IconSun,
  IconUser,
} from '@arco-design/web-vue/es/icon'

import DeveloperModeTools from '@/components/portal/DeveloperModeTools.vue'
import FlashMessages from '@/components/portal/FlashMessages.vue'
import LanguageSwitcher from '@/components/portal/LanguageSwitcher.vue'
import PortalAnnouncements from '@/components/portal/PortalAnnouncements.vue'
import {
  useApplicationShell,
  type ApplicationShellNavigationItem,
} from '@/lib/applicationShell'
import { useArcoLocale } from '@/lib/i18n'
import { routes } from '@/lib/routes'
import { safeSignOut } from '@/lib/safeSignOut'
import { useTheme } from '@/lib/useTheme'

const page = usePage()
const { t } = useI18n()
const arcoLocale = useArcoLocale()
const shell = useApplicationShell()
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
const developerMode = computed(() => (
  page.props.developer_mode ?? { enabled: false }
) as { enabled: boolean })
const currentPath = computed(() => page.url.split('?')[0])
const visibleGroups = computed(() => shell.navigation
  .map((group) => ({
    ...group,
    items: group.items.filter((item) => !item.requiresAuthentication || auth.value.user),
  }))
  .filter((group) => group.items.length > 0))
const allItems = computed(() => visibleGroups.value.flatMap((group) => group.items))
const selectedKey = computed(() => allItems.value
  .filter((item) => currentPath.value === item.href || currentPath.value.startsWith(`${item.href}/`))
  .sort((left, right) => right.href.length - left.href.length)[0]?.href)

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
  compact.value = event?.matches ?? compactQuery?.matches ?? false
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
  <ConfigProvider :locale="arcoLocale" global>
    <DeveloperModeTools v-if="developerMode.enabled" />
    <Layout class="mc-shell-layout" :style="{ minHeight: '100dvh' }">
      <LayoutSider
        v-if="!compact"
        class="mc-shell-sidebar"
        :width="'var(--mc-shell-sidebar-width, 248px)'"
        :style="{
          position: 'fixed',
          inset: '0 auto 0 0',
          zIndex: 30,
          borderRight: '1px solid var(--color-border-2)',
          background: 'var(--color-bg-2)',
        }"
      >
        <Space align="center" :size="10" :style="{ height: '60px', padding: '0 18px' }">
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
          :style="{
            position: 'sticky',
            top: 0,
            zIndex: 20,
            height: '60px',
            padding: '0 20px',
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
                <template #icon><IconShoppingCart /></template>
              </Button>
            </Badge>
            <Dropdown v-if="auth.user" trigger="click" position="br">
              <Button type="text" shape="round">
                <Space align="center" :size="8">
                  <Avatar :size="28" :image-url="auth.user.avatar_url || undefined">
                    {{ auth.user.username.slice(0, 2).toUpperCase() }}
                  </Avatar>
                  <TypographyText>{{ auth.user.username }}</TypographyText>
                </Space>
              </Button>
              <template #content>
                <Doption disabled><IconUser /> {{ auth.user.username }}</Doption>
                <Doption @click="visit(routes.account)"><IconApps /> {{ t('nav.personal') }}</Doption>
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

        <PortalAnnouncements
          v-if="shell.applicationId === 'forum'"
          :authenticated="!!auth.user"
          :announcements="globalAnnouncements"
          :notices="forumNotices"
        />

        <LayoutContent
          id="application-content"
          class="mc-page-content mc-page-surface"
          tabindex="-1"
          :style="{ padding: 'var(--mc-page-gutter, 24px)', minHeight: 'calc(100dvh - 60px)' }"
        >
          <div class="mc-page-container" :style="{ maxWidth: '1440px', margin: '0 auto' }">
            <FlashMessages />
            <slot />
          </div>
        </LayoutContent>
      </Layout>
    </Layout>

    <Drawer
      v-model:visible="mobileNavOpen"
      placement="left"
      :width="'min(280px, 100vw)'"
      :footer="false"
      unmount-on-close
    >
      <template #title>{{ t(shell.brandKey) }}</template>
      <template v-for="group in visibleGroups" :key="`mobile-${group.id}`">
        <TypographyText type="secondary">{{ t(group.labelKey) }}</TypographyText>
        <Menu :selected-keys="selectedKey ? [selectedKey] : []" @menu-item-click="visit">
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
    </Drawer>

    <component :is="shell.accessory" v-if="shell.accessory" />
  </ConfigProvider>
</template>
