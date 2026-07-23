<script setup lang="ts">
/**
 * Standalone Arco admin shell — no Inertia / vue-router.
 * Adapted from app/javascript/layouts/ArcoAdminLayout.vue.
 */
import { computed, ref, watch } from 'vue'
import {
  IconApps,
  IconBook,
  IconCommand,
  IconMenuFold,
  IconMenuUnfold,
  IconMoon,
  IconSun,
} from '@arco-design/web-vue/es/icon'

interface NavItem {
  label: string
  key: string
}
interface NavGroup {
  key: string
  label: string
  items: NavItem[]
}

const STORAGE_KEY = 'mc-arco-demo-nav-open'

const collapsed = ref(false)
const mobileNavOpen = ref(false)
const currentPath = ref('#demo')
const openKeys = ref<string[]>(loadOpen())

const nav: NavGroup[] = [
  {
    key: 'overview',
    label: '概览',
    items: [
      { label: 'Arco UI 范例', key: '#demo' },
      { label: '仪表盘', key: '#dashboard' },
      { label: '用户管理', key: '#users' },
    ],
  },
  {
    key: 'store',
    label: '商城',
    items: [
      { label: '商品', key: '#products' },
      { label: '订单', key: '#orders' },
      { label: '优惠券', key: '#coupons' },
    ],
  },
  {
    key: 'system',
    label: '系统',
    items: [
      { label: '设置', key: '#settings' },
      { label: '审计日志', key: '#audit' },
    ],
  },
]

const trailingCrumbs = computed(() => {
  for (const group of nav) {
    const item = group.items.find((it) => it.key === currentPath.value)
    if (item) return [{ label: group.label }, { label: item.label }]
  }
  return [{ label: 'Arco UI 范例' }]
})

function readInitialDark(): boolean {
  if (typeof document === 'undefined') return false
  const stored = localStorage.getItem('mc-theme')
  if (stored === 'dark') return true
  if (stored === 'light') return false
  return document.documentElement.classList.contains('dark')
}

const isDark = ref(readInitialDark())

function loadOpen(): string[] {
  try {
    const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]')
    return Array.isArray(raw) ? (raw as string[]) : ['overview']
  } catch {
    return ['overview']
  }
}

watch(openKeys, (keys) => {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(keys))
})

function onMenuClick(key: string) {
  mobileNavOpen.value = false
  currentPath.value = key
}

function toggleTheme() {
  const next = isDark.value ? 'light' : 'dark'
  document.documentElement.classList.toggle('dark', next === 'dark')
  localStorage.setItem('mc-theme', next)
  isDark.value = next === 'dark'
  syncArcoTheme()
}

function syncArcoTheme() {
  if (typeof document === 'undefined') return
  document.body.setAttribute('arco-theme', isDark.value ? 'dark' : '')
}

watch(isDark, syncArcoTheme, { immediate: true })
</script>

<template>
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
        <a href="#" class="arco-admin-brand__link" @click.prevent>
          <icon-command class="arco-admin-brand__icon" />
          <span v-show="!collapsed" class="arco-admin-brand__text">McWeb Admin</span>
        </a>
      </div>
      <div class="arco-admin-sider__menu">
        <a-menu
          :selected-keys="[currentPath]"
          v-model:open-keys="openKeys"
          :collapsed="collapsed"
          @menu-item-click="onMenuClick"
        >
          <a-sub-menu v-for="group in nav" :key="group.key">
            <template #icon><icon-apps /></template>
            <template #title>{{ group.label }}</template>
            <a-menu-item v-for="item in group.items" :key="item.key">
              {{ item.label }}
            </a-menu-item>
          </a-sub-menu>
        </a-menu>
      </div>
      <div v-show="!collapsed" class="arco-admin-sider__footer">
        <span>demo-admin</span>
        <span> · </span>
        <a href="#" @click.prevent>返回站点</a>
      </div>
    </a-layout-sider>

    <a-layout>
      <a-layout-header class="arco-admin-header">
        <div class="arco-admin-header__left">
          <a-button
            class="md:hidden"
            type="text"
            aria-label="打开菜单"
            @click="mobileNavOpen = true"
          >
            <template #icon><icon-menu-unfold /></template>
          </a-button>
          <a-button
            class="hidden md:inline-flex"
            type="text"
            :aria-label="collapsed ? '展开侧栏' : '收起侧栏'"
            @click="collapsed = !collapsed"
          >
            <template #icon>
              <icon-menu-unfold v-if="collapsed" />
              <icon-menu-fold v-else />
            </template>
          </a-button>
          <a-breadcrumb>
            <a-breadcrumb-item>管理后台</a-breadcrumb-item>
            <a-breadcrumb-item v-for="crumb in trailingCrumbs" :key="crumb.label">
              {{ crumb.label }}
            </a-breadcrumb-item>
          </a-breadcrumb>
        </div>
        <div class="arco-admin-header__right">
          <a-tag color="arcoblue" size="small">独立演示</a-tag>
          <a-button type="text" aria-label="切换主题" @click="toggleTheme">
            <template #icon>
              <icon-moon v-if="isDark" />
              <icon-sun v-else />
            </template>
          </a-button>
        </div>
      </a-layout-header>

      <a-layout-content class="arco-admin-main">
        <div class="arco-admin-main__inner">
          <slot />
        </div>
      </a-layout-content>
    </a-layout>
  </a-layout>

  <a-drawer
    v-model:visible="mobileNavOpen"
    placement="left"
    :width="260"
    :footer="false"
    :header="false"
    unmount-on-close
  >
    <div class="arco-admin-brand arco-admin-brand--drawer">
      <a href="#" class="arco-admin-brand__link" @click.prevent="mobileNavOpen = false">
        <icon-command class="arco-admin-brand__icon" />
        <span class="arco-admin-brand__text">McWeb Admin</span>
      </a>
    </div>
    <a-menu
      :selected-keys="[currentPath]"
      :default-open-keys="openKeys"
      @menu-item-click="onMenuClick"
    >
      <a-sub-menu v-for="group in nav" :key="`m-${group.key}`">
        <template #icon><icon-book /></template>
        <template #title>{{ group.label }}</template>
        <a-menu-item v-for="item in group.items" :key="item.key">
          {{ item.label }}
        </a-menu-item>
      </a-sub-menu>
    </a-menu>
    <div class="arco-admin-sider__footer">
      <span>demo-admin</span>
      <span> · </span>
      <a href="#" @click.prevent="mobileNavOpen = false">返回站点</a>
    </div>
  </a-drawer>
</template>

<style scoped>
.arco-admin-layout {
  background: var(--color-bg-1);
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

.arco-admin-main__inner {
  max-width: 1200px;
  margin: 0 auto;
}
</style>
