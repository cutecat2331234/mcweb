<script setup lang="ts">
import { Drawer } from '@mcweb/ui'
import ApplicationPortalNavigation from './ApplicationPortalNavigation.vue'
import type { PortalNavigationDestination, PortalNavigationGroup } from '@/lib/portalNavigationContributions'

defineProps<{
  brandLabel: string
  applicationId: string
  applicationLabel: string
  logoUrl?: string | null
  destinations: PortalNavigationDestination[]
  groups: PortalNavigationGroup[]
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
    class="mc-portal-mobile-navigation"
  >
    <template #title>{{ brandLabel }}</template>
    <ApplicationPortalNavigation
      :brand="brandLabel"
      :logo-url="logoUrl"
      :application-id="applicationId"
      :application-label="applicationLabel"
      :destinations="destinations"
      :groups="groups"
      :selected-key="selectedKey"
      @select="select"
    />
  </Drawer>
</template>
