<script setup lang="ts">
import { ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import Button from '@/components/ui/Button.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  profile: {
    username: string
    display_name: string | null
    forum_title: string | null
    avatar_url: string
    bio: string | null
    trust_level: number
    trust_name: string
    likes_received: number
    member_since: string
    topics_count: number
    posts_count: number
    profile_url: string
    message_url: string | null
    block_url: string | null
    is_blocked: boolean
    is_muted: boolean
    can_edit: boolean
    is_following: boolean
    follow_url: string | null
  }
  topics: Array<{
    id: string
    title: string
    url: string
    replies_count: number
    last_posted_at: string | null
  }>
  recent_posts: Array<{
    id: number
    body: string
    floor_number: number
    topic_title: string
    topic_url: string
    created_at: string
  }>
  liked_posts: Array<{
    id: number
    body: string
    floor_number: number
    topic_title: string
    topic_url: string
    likes_count: number
  }>
  badges: Array<{
    name: string
    icon: string
    description: string | null
    color: string
  }>
}>()

const editingBio = ref(false)
const editingTitle = ref(false)
const bioForm = useForm({ user: { bio: props.profile.bio || '', forum_title: props.profile.forum_title || '' } })

function toggleBlock() {
  if (!props.profile.block_url) return
  router.post(props.profile.block_url, {}, { preserveScroll: true })
}

function toggleFollow() {
  if (!props.profile.follow_url) return
  router.post(props.profile.follow_url, {}, { preserveScroll: true })
}

function saveBio() {
  bioForm.patch(`/forum/users/${props.profile.username}`, {
    preserveScroll: true,
    onSuccess: () => {
      editingBio.value = false
      editingTitle.value = false
    },
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: profile.username, current: true },
  ]" />

  <p v-if="profile.is_muted" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    你当前被禁言，暂时无法发帖。
  </p>

  <div class="mb-6 flex items-center gap-4">
    <img :src="profile.avatar_url" :alt="profile.username" class="h-16 w-16 rounded-full" />
    <div class="min-w-0 flex-1">
      <PageHeader
        :title="profile.display_name || profile.username"
        :subtitle="`${profile.forum_title ? profile.forum_title + ' · ' : ''}加入于 ${profile.member_since} · ${profile.trust_name} (Lv.${profile.trust_level})`"
      />
      <div class="mt-2 flex gap-6 text-sm">
        <span><strong>{{ profile.topics_count }}</strong> 主题</span>
        <span><strong>{{ profile.posts_count }}</strong> 帖子</span>
        <span><strong>{{ profile.likes_received }}</strong> 获赞</span>
      </div>
      <div v-if="badges.length" class="mt-3 flex flex-wrap gap-2">
        <span
          v-for="badge in badges"
          :key="badge.name"
          class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs"
          :style="{ borderColor: badge.color, color: badge.color }"
          :title="badge.description || badge.name"
        >
          {{ badge.icon }} {{ badge.name }}
        </span>
      </div>
      <div class="mt-3 flex flex-wrap gap-2">
        <Button v-if="profile.message_url" as-child size="sm">
          <Link :href="profile.message_url">发私信</Link>
        </Button>
        <Button
          v-if="profile.follow_url"
          type="button"
          size="sm"
          :variant="profile.is_following ? 'outline' : 'default'"
          @click="toggleFollow"
        >
          {{ profile.is_following ? '取消关注' : '关注' }}
        </Button>
        <Button
          v-if="profile.block_url"
          type="button"
          size="sm"
          :variant="profile.is_blocked ? 'outline' : 'destructive'"
          @click="toggleBlock"
        >
          {{ profile.is_blocked ? '取消拉黑' : '拉黑用户' }}
        </Button>
        <Button v-if="profile.can_edit" type="button" size="sm" variant="outline" @click="editingTitle = !editingTitle">
          编辑头衔
        </Button>
        <Button v-if="profile.can_edit" type="button" size="sm" variant="outline" @click="editingBio = !editingBio">
          编辑简介
        </Button>
      </div>
    </div>
  </div>

  <form v-if="editingTitle" class="mb-6 max-w-xl space-y-3 rounded-lg border p-4" @submit.prevent="saveBio">
    <Label for="forum_title">论坛头衔</Label>
    <input id="forum_title" v-model="bioForm.user.forum_title" class="h-9 w-full rounded-md border px-2 text-sm" placeholder="如：资深玩家" />
    <div class="flex gap-2">
      <Button type="submit" size="sm" :disabled="bioForm.processing">保存</Button>
      <Button type="button" size="sm" variant="outline" @click="editingTitle = false">取消</Button>
    </div>
  </form>

  <div v-if="profile.bio && !editingBio" class="mb-6 max-w-xl rounded-lg border p-4 text-sm whitespace-pre-wrap">
    {{ profile.bio }}
  </div>

  <form v-if="editingBio" class="mb-6 max-w-xl space-y-3 rounded-lg border p-4" @submit.prevent="saveBio">
    <Label for="bio">个人简介</Label>
    <Textarea id="bio" v-model="bioForm.user.bio" rows="4" placeholder="介绍一下自己…" />
    <div class="flex gap-2">
      <Button type="submit" size="sm" :disabled="bioForm.processing">保存</Button>
      <Button type="button" size="sm" variant="outline" @click="editingBio = false">取消</Button>
    </div>
  </form>

  <h2 class="mb-3 text-sm font-semibold">最近主题</h2>
  <div v-if="topics.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>标题</TableHead>
          <TableHead>回复</TableHead>
          <TableHead>最后回复</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="topic in topics" :key="topic.id">
          <TableCell><Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link></TableCell>
          <TableCell>{{ topic.replies_count }}</TableCell>
          <TableCell>{{ topic.last_posted_at || '—' }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无主题。</p>

  <h2 class="mb-3 mt-8 text-sm font-semibold">最近回复</h2>
  <div v-if="recent_posts.length" class="space-y-2 rounded-lg border p-4">
    <div v-for="post in recent_posts" :key="post.id" class="text-sm">
      <Link :href="post.topic_url" class="font-medium hover:underline">#{{ post.floor_number }} {{ post.topic_title }}</Link>
      <p class="text-muted-foreground">{{ post.body }}</p>
      <p class="text-xs text-muted-foreground">{{ post.created_at }}</p>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无回复。</p>

  <h2 class="mb-3 mt-8 text-sm font-semibold">获赞帖子</h2>
  <div v-if="liked_posts.length" class="space-y-2 rounded-lg border p-4">
    <div v-for="post in liked_posts" :key="post.id" class="text-sm">
      <Link :href="post.topic_url" class="font-medium hover:underline">#{{ post.floor_number }} {{ post.topic_title }}</Link>
      <span class="ml-2 text-xs text-muted-foreground">{{ post.likes_count }} 个反应</span>
      <p class="text-muted-foreground">{{ post.body }}</p>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无获赞帖子。</p>
</template>
