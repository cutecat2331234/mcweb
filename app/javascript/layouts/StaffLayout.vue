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
  Modal,
  Space,
  TypographyParagraph,
  TypographyText,
} from '@mcweb/ui'
import {
  IconApps,
  IconCommand,
  IconHome,
  IconMenu,
  IconMoon,
  IconPoweroff,
  IconSafe,
  IconSun,
  IconUser,
} from '@arco-design/web-vue/es/icon'
import { routes } from '@/lib/routes'
import { useTheme } from '@/lib/useTheme'

const page = usePage()
const { t } = useI18n()
const { isDark, toggleTheme } = useTheme()
const mobileNavOpen = ref(false)
const signOutVisible = ref(false)
const signingOut = ref(false)
const isCompact = ref(false)
let compactQuery: MediaQueryList | null = null

const auth = computed(
  () => (page.props.auth ?? { user: null }) as {
    user: { username: string; avatar_url?: string | null } | null
  },
)
const currentPath = computed(() => page.url.split('?')[0])
const selectedKey = computed(() =>
  currentPath.value.startsWith(routes.staffModerationCases)
    ? routes.staffModerationCases
    : routes.staff,
)
const currentTitle = computed(() =>
  selectedKey.value === routes.staffModerationCases
    ? t('staffWorkspace.navigation.queue')
    : t('staffWorkspace.navigation.overview'),
)

function visit(path: string) {
  mobileNavOpen.value = false
  if (currentPath.value === path) return
  router.visit(path)
}

function onMenuClick(key: string) {
  visit(key)
}

function onToggleTheme() {
  toggleTheme()
  syncArcoTheme()
}

function syncArcoTheme() {
  if (typeof document === 'undefined') return
  document.body.setAttribute('arco-theme', isDark.value ? 'dark' : '')
}

function confirmSignOut() {
  signingOut.value = true
  router.delete(routes.signOut, {
    onFinish: () => {
      signingOut.value = false
      signOutVisible.value = false
    },
  })
  return false
}

function syncCompactLayout(event?: MediaQueryListEvent) {
  isCompact.value = event?.matches ?? compactQuery?.matches ?? false
}

onMounted(() => {
  compactQuery = window.matchMedia('(max-width: 991px)')
  syncCompactLayout()
  compactQuery.addEventListener('change', syncCompactLayout)
})

onBeforeUnmount(() => {
  compactQuery?.removeEventListener('change', syncCompactLayout)
})

watch(isDark, syncArcoTheme, { immediate: true })
</script>

<template>
  <ConfigProvider>
    <Layout
      class="mc-shell-layout"
      :style="{ minHeight: '100dvh', background: 'var(--color-bg-1)' }"
    >
      <LayoutSider
        v-if="!isCompact"
        class="mc-shell-sidebar"
        breakpoint="lg"
        :width="'var(--mc-shell-sidebar-width, 248px)'"
        :collapsed-width="0"
        :hide-trigger="true"
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
          :size="12"
          :style="{
            height: 'var(--mc-shell-topbar-height, 60px)',
            padding: '0 var(--mc-shell-header-padding-inline, 20px)',
            width: '100%',
            boxSizing: 'border-box',
          }"
        >
          <IconCommand :size="24" />
          <TypographyText bold>{{ t('staffWorkspace.brand') }}</TypographyText>
        </Space>
        <Menu
          :selected-keys="[selectedKey]"
          :style="{ borderRight: 0, padding: 'var(--mc-space-2, 8px)' }"
          @menu-item-click="onMenuClick"
        >
          <MenuItem :key="routes.staff">
            <template #icon><IconHome /></template>
            {{ t('staffWorkspace.navigation.overview') }}
          </MenuItem>
          <MenuItem :key="routes.staffModerationCases">
            <template #icon><IconSafe /></template>
            {{ t('staffWorkspace.navigation.queue') }}
          </MenuItem>
        </Menu>
        <Space
          direction="vertical"
          fill
          :size="8"
          :style="{
            position: 'absolute',
            inset: 'auto var(--mc-space-3, 12px) var(--mc-space-4, 16px)',
          }"
        >
          <Button long @click="visit(routes.forum)">
            <template #icon><IconApps /></template>
            {{ t('staffWorkspace.returnToApp') }}
          </Button>
        </Space>
      </LayoutSider>

      <Layout
        :style="{
          marginLeft: isCompact ? '0' : 'var(--mc-shell-sidebar-width, 248px)',
          width: isCompact ? '100%' : 'calc(100% - var(--mc-shell-sidebar-width, 248px))',
          minWidth: 0,
        }"
      >
        <LayoutHeader
          class="mc-shell-header"
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
              type="text"
              shape="circle"
              :aria-label="t('common.openMenu')"
              :style="{ display: isCompact ? 'inline-flex' : 'none' }"
              @click="mobileNavOpen = true"
            >
              <template #icon><IconMenu /></template>
            </Button>
            <TypographyText bold>{{ currentTitle }}</TypographyText>
            <Badge status="processing" :text="t('staffWorkspace.badge')" />
          </Space>

          <Space align="center" :size="4">
            <Button
              type="text"
              shape="circle"
              :aria-label="t('common.toggleTheme')"
              @click="onToggleTheme"
            >
              <template #icon><IconSun v-if="isDark" /><IconMoon v-else /></template>
            </Button>
            <Dropdown v-if="auth.user" trigger="click" position="br">
              <Button type="text" shape="round">
                <Space align="center" :size="8">
                  <Avatar
                    :size="30"
                    shape="circle"
                    :image-url="auth.user.avatar_url || undefined"
                  >
                    {{ auth.user.username.slice(0, 2).toUpperCase() }}
                  </Avatar>
                  <TypographyText>{{ auth.user.username }}</TypographyText>
                </Space>
              </Button>
              <template #content>
                <Doption disabled><IconUser /> {{ auth.user.username }}</Doption>
                <Doption @click="visit(routes.forum)">
                  <IconApps /> {{ t('staffWorkspace.returnToApp') }}
                </Doption>
                <Doption @click="signOutVisible = true">
                  <IconPoweroff /> {{ t('common.signOut') }}
                </Doption>
              </template>
            </Dropdown>
          </Space>
        </LayoutHeader>

        <LayoutContent
          id="staff-content"
          class="mc-page-content mc-page-surface"
          tabindex="-1"
          :style="{
            padding: 'var(--mc-page-gutter, 24px)',
            minHeight: 'calc(100dvh - var(--mc-shell-topbar-height, 60px))',
          }"
        >
          <div
            class="mc-page-container"
            :style="{
              width: '100%',
              maxWidth: 'var(--mc-page-max-width, 1440px)',
              margin: '0 auto',
            }"
          >
            <slot />
          </div>
        </LayoutContent>
      </Layout>
    </Layout>

    <Drawer
      v-model:visible="mobileNavOpen"
      placement="left"
      :width="'min(var(--mc-shell-drawer-width, 280px), 100vw)'"
      :footer="false"
      unmount-on-close
    >
      <template #title>{{ t('staffWorkspace.brand') }}</template>
      <Menu :selected-keys="[selectedKey]" @menu-item-click="onMenuClick">
        <MenuItem :key="routes.staff">
          <template #icon><IconHome /></template>
          {{ t('staffWorkspace.navigation.overview') }}
        </MenuItem>
        <MenuItem :key="routes.staffModerationCases">
          <template #icon><IconSafe /></template>
          {{ t('staffWorkspace.navigation.queue') }}
        </MenuItem>
      </Menu>
    </Drawer>

    <Modal
      v-model:visible="signOutVisible"
      :title="t('common.signOutConfirmTitle')"
      :ok-text="t('common.signOut')"
      :cancel-text="t('common.cancel')"
      :ok-loading="signingOut"
      :ok-button-props="{ status: 'danger' }"
      :on-before-ok="confirmSignOut"
      align-center
      unmount-on-close
    >
      <TypographyParagraph>
        {{ t('common.signOutConfirmDescription') }}
      </TypographyParagraph>
    </Modal>
  </ConfigProvider>
</template>
