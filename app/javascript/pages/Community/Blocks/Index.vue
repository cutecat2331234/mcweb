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
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '拉黑列表', current: true },
  ]" />

  <PageHeader title="拉黑列表" subtitle="你拉黑的用户将不会出现在主题流与私信中" />

  <div v-if="users.length" class="divide-y rounded-lg border">
    <div v-for="user in users" :key="user.username" class="flex items-center justify-between gap-4 p-4">
      <div>
        <Link :href="user.profile_url" class="font-medium hover:underline">{{ user.display_name || user.username }}</Link>
        <p class="text-xs text-muted-foreground">拉黑于 {{ user.blocked_at }}</p>
      </div>
      <Button type="button" variant="outline" size="sm" @click="unblock(user.unblock_url)">取消拉黑</Button>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">你还没有拉黑任何用户。</p>
</template>
