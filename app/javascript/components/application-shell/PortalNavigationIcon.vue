<script setup lang="ts">
import { computed, type Component } from 'vue'
import {
  IconApps, IconArchive, IconBarChart, IconBook, IconBookmark, IconCommand,
  IconEmail, IconFile, IconFire, IconGift, IconHeart, IconHistory, IconHome,
  IconIdcard, IconList, IconLock, IconMessage, IconNotification, IconSafe,
  IconSearch, IconSettings, IconTag, IconTrophy, IconUser, IconUserGroup,
} from '@arco-design/web-vue/es/icon'

const props = defineProps<{ name?: string }>()
const icons: Record<string, Component> = {
  apps: IconApps, archive: IconArchive, chart: IconBarChart, book: IconBook,
  bookmark: IconBookmark, command: IconCommand, email: IconEmail, file: IconFile,
  fire: IconFire, gift: IconGift, heart: IconHeart, history: IconHistory,
  home: IconHome, wallet: IconIdcard, list: IconList, lock: IconLock,
  message: IconMessage, notification: IconNotification, safe: IconSafe,
  search: IconSearch, settings: IconSettings, tag: IconTag, trophy: IconTrophy,
  user: IconUser, users: IconUserGroup,
}
const icon = computed(() => icons[props.name ?? ''] ?? IconFile)
</script>

<template><component :is="icon" aria-hidden="true" /></template>
