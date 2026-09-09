<script setup lang="ts">
import {
  Badge,
  Drawer,
  Menu,
  MenuItem,
  TypographyText,
} from '@mcweb/ui'

type MobileNavigationItem = {
  href: string
  label: string
  badge: number
}

type MobileNavigationGroup = {
  id: string
  label: string
  items: MobileNavigationItem[]
}

defineProps<{
  brandLabel: string
  groups: MobileNavigationGroup[]
  selectedKey?: string
}>()

const visible = defineModel<boolean>('visible', { required: true })
const emit = defineEmits<{ select: [path: string] }>()

function select(path: string) {
  visible.value = false
  emit('select', path)
}
</script>

<template>
  <Drawer
    v-model:visible="visible"
    placement="left"
    :width="'min(var(--mc-shell-drawer-width, 280px), 100vw)'"
    :footer="false"
    :aria-label="brandLabel"
    aria-modal="true"
    role="dialog"
    unmount-on-close
  >
    <template #title>{{ brandLabel }}</template>
    <template v-for="group in groups" :key="group.id">
      <TypographyText type="secondary">{{ group.label }}</TypographyText>
      <Menu
        data-mc-application-navigation
        :data-navigation-group="group.id"
        :selected-keys="selectedKey ? [selectedKey] : []"
        @menu-item-click="select"
      >
        <MenuItem v-for="item in group.items" :key="item.href">
          <span :style="{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px' }">
            <span>{{ item.label }}</span>
            <Badge v-if="item.badge > 0" :count="item.badge" :max-count="99" />
          </span>
        </MenuItem>
      </Menu>
    </template>
  </Drawer>
</template>
