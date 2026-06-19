<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

defineProps<{
  users: Array<{
    username: string
    display_name: string | null
    profile_url: string
    blocked_at: string
    unblock_url: string
  }>
}>()

function unblock(url: string) {
  router.post(url, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.blocks.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.blocks.title')" :subtitle="t('forum.blocks.subtitle')" />

  <div v-if="users.length" class="divide-y rounded-lg border">
    <div v-for="user in users" :key="user.username" class="flex items-center justify-between gap-4 p-4">
      <div>
        <Link :href="user.profile_url" class="font-medium hover:underline">{{ user.display_name || user.username }}</Link>
        <p class="text-xs text-muted-foreground">{{ t('forum.blocks.blockedAt', { at: user.blocked_at }) }}</p>
      </div>
      <Button type="button" variant="outline" size="sm" @click="unblock(user.unblock_url)">{{ t('forum.blocks.unblock') }}</Button>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('forum.blocks.empty') }}</p>
</template>
