<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  users: Array<{
    username: string
    display_name: string | null
    profile_url: string
    ignored_at: string
    unignore_url: string
  }>
}>()

function unignore(url: string) {
  router.post(url, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '忽略列表', current: true },
  ]" />

  <PageHeader title="忽略列表" subtitle="你忽略的用户将不会出现在主题流中（仍可访问其资料页）" />

  <div v-if="users.length" class="divide-y rounded-lg border">
    <div v-for="user in users" :key="user.username" class="flex items-center justify-between gap-4 p-4">
      <div>
        <Link :href="user.profile_url" class="font-medium hover:underline">{{ user.display_name || user.username }}</Link>
        <p class="text-xs text-muted-foreground">忽略于 {{ user.ignored_at }}</p>
      </div>
      <Button type="button" variant="outline" size="sm" @click="unignore(user.unignore_url)">取消忽略</Button>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">你还没有忽略任何用户。</p>
</template>
