<script setup lang="ts">
import { reactive } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()
const processingUsers = reactive(new Set<string>())

defineProps<{
  users: Array<{
    username: string
    display_name: string | null
    profile_url: string
    ignored_at: string
    unignore_url: string
  }>
}>()

function unignore(user: { username: string; unignore_url: string }) {
  if (processingUsers.has(user.username)) return

  processingUsers.add(user.username)
  router.delete(user.unignore_url, {
    preserveScroll: true,
    onFinish: () => processingUsers.delete(user.username),
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.ignores.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.ignores.title')" :subtitle="t('forum.ignores.subtitle')" />

  <div v-if="users.length" class="divide-y rounded-lg border">
    <div v-for="user in users" :key="user.username" class="flex items-center justify-between gap-4 p-4">
      <div>
        <Link :href="user.profile_url" class="font-medium hover:underline">{{ user.display_name || user.username }}</Link>
        <p class="text-xs text-muted-foreground">{{ t('forum.ignores.ignoredAt', { at: user.ignored_at }) }}</p>
      </div>
      <Button type="button" variant="outline" size="sm" :disabled="processingUsers.has(user.username)" @click="unignore(user)">{{ t('forum.ignores.unignore') }}</Button>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('forum.ignores.empty') }}</p>
</template>
