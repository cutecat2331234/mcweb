<script setup lang="ts">
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { Badge, Button, Menu, MenuItem, MenuItemGroup, Scrollbar, SubMenu, Tooltip } from '@mcweb/ui'
import { IconCommand, IconHome, IconMenuFold, IconMenuUnfold } from '@arco-design/web-vue/es/icon'
import PortalNavigationIcon from './PortalNavigationIcon.vue'
import type { PortalNavigationDestination, PortalNavigationGroup } from '@/lib/portalNavigationContributions'

const props = defineProps<{
  brand: string
  logoUrl?: string | null
  applicationId: string
  applicationLabel: string
  destinations: PortalNavigationDestination[]
  groups: PortalNavigationGroup[]
  selectedKey?: string
  collapsed?: boolean
  collapsible?: boolean
}>()
const emit = defineEmits<{ select: [path: string]; toggleCollapsed: [] }>()
const { t } = useI18n()
const openKeys = ref<string[]>([])
watch(() => props.applicationId, (id) => { openKeys.value = [`application:${id}`] }, { immediate: true })
</script>

<template>
  <nav class="mc-portal-navigation" :data-collapsed="collapsed" :aria-label="t('common.navigation')">
    <div class="mc-portal-brand">
      <span class="mc-portal-brand-mark" aria-hidden="true">
        <img v-if="logoUrl" :src="logoUrl" alt="" />
        <IconCommand v-else :size="24" />
      </span>
      <div v-if="!collapsed" class="mc-portal-brand-copy">
        <strong :title="brand">{{ brand }}</strong>
        <span :title="applicationLabel">{{ applicationLabel }}</span>
      </div>
    </div>

    <div class="mc-portal-navigation-scroll">
      <Scrollbar :style="{ height: '100%' }" :disable-horizontal="true">
        <Menu
          v-model:open-keys="openKeys"
          class="mc-portal-menu"
          data-mc-application-navigation
          :selected-keys="selectedKey ? [selectedKey] : []"
          :collapsed="collapsed"
          :collapsed-width="64"
          :tooltip-props="{ position: 'right' }"
          :trigger-props="{ position: 'right', class: 'mc-portal-navigation-popup' }"
          :popup-max-height="480"
          auto-open-selected
          @menu-item-click="emit('select', $event)"
        >
          <template v-for="destination in destinations" :key="destination.id">
            <SubMenu
              v-if="destination.id === applicationId && groups.length"
              :key="`application:${destination.id}`"
              :aria-label="destination.label"
            >
              <template #icon><PortalNavigationIcon :name="destination.icon" /></template>
              <template #title>{{ destination.label }}</template>
              <MenuItemGroup v-for="group in groups" :key="group.id" :data-navigation-group="group.id" :title="groups.length > 1 ? group.label : undefined">
                <MenuItem
                  v-for="item in group.items"
                  :key="item.href"
                  :aria-label="item.label"
                  :aria-current="item.href === selectedKey ? 'page' : undefined"
                >
                  <template #icon><PortalNavigationIcon :name="item.icon" /></template>
                  <span class="mc-portal-menu-label">{{ item.label }}</span>
                  <Badge v-if="item.badge > 0" :count="item.badge" :max-count="99" />
                </MenuItem>
              </MenuItemGroup>
            </SubMenu>
            <MenuItem v-else :key="destination.href" :aria-label="destination.label">
              <template #icon><PortalNavigationIcon :name="destination.icon" /></template>
              {{ destination.label }}
              <Badge v-if="destination.badge" :count="destination.badge" :max-count="99" />
            </MenuItem>
          </template>
        </Menu>
      </Scrollbar>
    </div>

    <div class="mc-portal-navigation-footer">
      <Tooltip :content="t('common.backToSite')" position="right" :disabled="!collapsed">
        <Button type="text" :long="!collapsed" href="/" data-mcweb-document-navigation :aria-label="t('common.backToSite')">
          <template #icon><IconHome /></template>
          <span v-if="!collapsed">{{ t('common.backToSite') }}</span>
        </Button>
      </Tooltip>
      <Tooltip v-if="collapsible" :content="t(collapsed ? 'common.expandNavigation' : 'common.collapseNavigation')" position="right" :disabled="!collapsed">
        <Button type="text" :long="!collapsed" :aria-label="t(collapsed ? 'common.expandNavigation' : 'common.collapseNavigation')" data-mc-navigation-collapse @click="emit('toggleCollapsed')">
          <template #icon><IconMenuUnfold v-if="collapsed" /><IconMenuFold v-else /></template>
          <span v-if="!collapsed">{{ t('common.collapseNavigation') }}</span>
        </Button>
      </Tooltip>
    </div>
  </nav>
</template>
