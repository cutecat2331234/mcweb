<script setup lang="ts">
import { ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Input from '@/components/ui/Input.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  members: Array<{
    username: string
    display_name: string | null
    avatar_url: string
    profile_url: string
    last_seen_at: string | null
    online: boolean
    posts_count: number
    likes_received: number
    reviews_count: number
    purchases_count: number
    trust_level: number
    trust_name: string
    member_since: string
  }>
  pagination: PaginationMeta
  query: string
  sort: string
  trustLevel?: string
}>()

const searchQuery = ref(props.query)

const sortOptions = [
  { value: 'active', label: '最近活跃' },
  { value: 'online', label: '当前在线' },
  { value: 'joined', label: '最新加入' },
  { value: 'posts', label: '发帖最多' },
  { value: 'likes', label: '获赞最多' },
  { value: 'reviews', label: '评价最多' },
  { value: 'purchases', label: '购买最多' },
]

const trustLevelOptions = [
  { value: '', label: '全部信任等级' },
  { value: '0', label: 'TL0 新成员' },
  { value: '1', label: 'TL1 基本用户' },
  { value: '2', label: 'TL2 成员' },
  { value: '3', label: 'TL3 常客' },
  { value: '4', label: 'TL4 领导者' },
]

function search() {
  router.get(routes.forumMembers, {
    q: searchQuery.value || undefined,
    sort: props.sort !== 'active' ? props.sort : undefined,
  }, { preserveState: true })
}

function changeSort(value: string) {
  router.get(routes.forumMembers, {
    q: searchQuery.value || undefined,
    sort: value !== 'active' ? value : undefined,
    trust_level: props.trustLevel || undefined,
  }, { preserveState: true })
}

function changeTrustLevel(value: string) {
  router.get(routes.forumMembers, {
    q: searchQuery.value || undefined,
    sort: props.sort !== 'active' ? props.sort : undefined,
    trust_level: value || undefined,
  }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '成员目录', current: true },
  ]" />

  <PageHeader title="成员目录" subtitle="浏览社区成员与在线状态" />

  <div class="mb-4 flex flex-wrap items-center gap-2">
    <form class="flex flex-1 gap-2" @submit.prevent="search">
      <Input v-model="searchQuery" placeholder="搜索用户名…" class="max-w-xs" />
      <Button type="submit" variant="outline">搜索</Button>
    </form>
    <Select :model-value="sort" :options="sortOptions" size="sm" @update:model-value="changeSort" />
    <Select :model-value="trustLevel || ''" :options="trustLevelOptions" size="sm" @update:model-value="changeTrustLevel" />
  </div>

  <div v-if="members.length" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
    <Link
      v-for="member in members"
      :key="member.username"
      :href="member.profile_url"
      class="flex items-center gap-3 rounded-lg border p-4 hover:bg-muted/50"
    >
      <img :src="member.avatar_url" :alt="member.username" class="h-12 w-12 rounded-full" />
      <div class="min-w-0">
        <p class="font-medium">
          {{ member.display_name || member.username }}
          <Badge v-if="member.online" class="ml-2 text-[10px]">在线</Badge>
        </p>
        <p class="text-xs text-muted-foreground">
          @{{ member.username }} · {{ member.trust_name }} · {{ member.posts_count }} 帖 · {{ member.likes_received }} 赞 · {{ member.purchases_count }} 购
        </p>
        <p class="text-xs text-muted-foreground">
          {{ member.reviews_count }} 评价 ·
          {{ member.last_seen_at ? `最后在线 ${member.last_seen_at}` : `加入于 ${member.member_since}` }}
        </p>
      </div>
    </Link>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">未找到成员。</p>

  <Pagination :pagination="pagination" :base-path="routes.forumMembers" />
</template>
