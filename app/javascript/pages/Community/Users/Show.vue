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
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  profile: {
    username: string
    display_name: string | null
    forum_title: string | null
    forum_flair_color_hex?: string | null
    avatar_url: string
    bio: string | null
    trust_level: number
    trust_name: string
    likes_received: number
    member_since: string
    last_seen_at?: string | null
    online?: boolean
    forum_signature?: string | null
    topics_count: number
    posts_count: number
    orders_count?: number
    followers_count?: number
    followers_url?: string | null
    profile_url: string
    message_url: string | null
    block_url: string | null
    ignore_url?: string | null
    is_blocked: boolean
    is_ignored?: boolean
    is_muted: boolean
    can_edit: boolean
    is_following: boolean
    follow_url: string | null
    mute_info?: {
      section: string
      reason: string | null
      expires_at: string
    } | null
    trust_progress?: {
      level: number
      name: string
      posts_count: number
      next_level: number | null
      next_level_name: string | null
      posts_needed: number
      can_send_pm: boolean
      can_post_links: boolean
    } | null
    warning_points?: number | null
  }
  warnings?: Array<{
    reason: string
    points: number
    issuer: string
    created_at: string
  }>
  topics: TopicListItem[]
  topicsPagination: PaginationMeta
  recent_posts: Array<{
    id: number
    body: string
    floor_number: number
    topic_title: string
    topic_url: string
    created_at: string
  }>
  postsPagination: PaginationMeta
  activeTab: 'topics' | 'posts' | 'store'
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
  store_reviews?: Array<{
    id: number
    product_name: string
    product_url: string
    rating: number
    body: string | null
    created_at: string
  }>
  store_orders?: Array<{
    order_number: string
    status_label: string
    total_label: string
    url: string
    created_at: string
  }>
}>()

const editingBio = ref(false)
const editingTitle = ref(false)
const editingSignature = ref(false)
const avatarInput = ref<HTMLInputElement | null>(null)
const bioForm = useForm({
  user: {
    bio: props.profile.bio || '',
    forum_title: props.profile.forum_title || '',
    forum_flair_color_hex: props.profile.forum_flair_color_hex || '',
    forum_signature: props.profile.forum_signature || '',
  },
})

function toggleBlock() {
  if (!props.profile.block_url) return
  router.post(props.profile.block_url, {}, { preserveScroll: true })
}

function toggleIgnore() {
  if (!props.profile.ignore_url) return
  router.post(props.profile.ignore_url, {}, { preserveScroll: true })
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
      editingSignature.value = false
    },
  })
}

function removeAvatar() {
  router.post(`/forum/users/${props.profile.username}`, {
    _method: 'patch',
    user: { remove_forum_avatar: true },
  }, { preserveScroll: true })
}

function uploadAvatar(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file) return
  const data = new FormData()
  data.append('_method', 'patch')
  data.append('user[forum_avatar]', file)
  router.post(`/forum/users/${props.profile.username}`, data, {
    forceFormData: true,
    preserveScroll: true,
    onFinish: () => {
      if (avatarInput.value) avatarInput.value.value = ''
    },
  })
}

function switchTab(tab: 'topics' | 'posts' | 'store') {
  router.get(`/forum/users/${props.profile.username}`, { tab }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: profile.username, current: true },
  ]" />

  <p v-if="profile.mute_info" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    你当前被禁言（{{ profile.mute_info.section }}）{{ profile.mute_info.reason ? '：' + profile.mute_info.reason : '' }}，到期：{{ profile.mute_info.expires_at }}
  </p>
  <p v-else-if="profile.is_muted" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    你当前被禁言，暂时无法发帖。
  </p>

  <div class="mb-6 flex items-center gap-4">
    <img :src="profile.avatar_url" :alt="profile.username" class="h-16 w-16 rounded-full" />
    <div class="min-w-0 flex-1">
      <PageHeader
        :title="profile.display_name || profile.username"
        :subtitle="`${profile.forum_title ? profile.forum_title + ' · ' : ''}加入于 ${profile.member_since}${profile.last_seen_at ? ' · 最后在线 ' + profile.last_seen_at : ''}${profile.online ? ' · 在线' : ''} · ${profile.trust_name} (Lv.${profile.trust_level})`"
      />
      <div class="mt-2 flex gap-6 text-sm">
        <span><strong>{{ profile.topics_count }}</strong> 主题</span>
        <span><strong>{{ profile.posts_count }}</strong> 帖子</span>
        <span v-if="profile.orders_count"><strong>{{ profile.orders_count }}</strong> 订单</span>
        <Link v-if="profile.followers_url" :href="profile.followers_url" class="hover:underline">
          <strong>{{ profile.followers_count ?? 0 }}</strong> 粉丝
        </Link>
        <span><strong>{{ profile.likes_received }}</strong> 获赞</span>
        <span v-if="profile.warning_points != null"><strong>{{ profile.warning_points }}</strong> 警告积分</span>
      </div>
      <div v-if="warnings?.length" class="mt-4 max-w-xl rounded-lg border p-4">
        <h3 class="mb-2 text-sm font-semibold">社区警告记录</h3>
        <ul class="space-y-2 text-sm">
          <li v-for="(warning, index) in warnings" :key="index" class="flex justify-between gap-4 border-b pb-2 last:border-0 last:pb-0">
            <span>{{ warning.reason }}</span>
            <span class="shrink-0 text-muted-foreground">{{ warning.points }} 点 · {{ warning.issuer }} · {{ warning.created_at }}</span>
          </li>
        </ul>
      </div>
      <div v-if="profile.trust_progress" class="mt-3 max-w-md rounded-lg border p-3 text-sm">
        <p class="font-medium">{{ profile.trust_progress.name }} (Lv.{{ profile.trust_progress.level }})</p>
        <p v-if="profile.trust_progress.posts_needed > 0" class="mt-1 text-muted-foreground">
          再发 {{ profile.trust_progress.posts_needed }} 帖可升至 {{ profile.trust_progress.next_level_name }}
        </p>
        <p v-else class="mt-1 text-muted-foreground">已达最高信任等级</p>
        <p class="mt-1 text-xs text-muted-foreground">
          {{ profile.trust_progress.can_send_pm ? '可发私信' : 'Lv.1 后可发私信' }} ·
          {{ profile.trust_progress.can_post_links ? '可发链接' : 'Lv.1 后可发链接' }}
        </p>
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
        <Button
          v-if="profile.ignore_url"
          type="button"
          size="sm"
          :variant="profile.is_ignored ? 'outline' : 'secondary'"
          @click="toggleIgnore"
        >
          {{ profile.is_ignored ? '取消忽略' : '忽略用户' }}
        </Button>
        <Button v-if="profile.can_edit" type="button" size="sm" variant="outline" @click="editingTitle = !editingTitle">
          编辑头衔
        </Button>
        <Button v-if="profile.can_edit" type="button" size="sm" variant="outline" @click="editingBio = !editingBio">
          编辑简介
        </Button>
        <Button v-if="profile.can_edit" type="button" size="sm" variant="outline" @click="editingSignature = !editingSignature">
          编辑签名
        </Button>
        <template v-if="profile.can_edit">
          <input ref="avatarInput" type="file" accept="image/*" class="hidden" @change="uploadAvatar" />
          <Button type="button" size="sm" variant="outline" @click="avatarInput?.click()">更换头像</Button>
          <Button type="button" size="sm" variant="outline" @click="removeAvatar">恢复默认头像</Button>
        </template>
      </div>
    </div>
  </div>

  <form v-if="editingTitle" class="mb-6 max-w-xl space-y-3 rounded-lg border p-4" @submit.prevent="saveBio">
    <Label for="forum_title">论坛头衔</Label>
    <input id="forum_title" v-model="bioForm.user.forum_title" class="h-9 w-full rounded-md border px-2 text-sm" placeholder="如：资深玩家" />
    <Label for="forum_flair_color_hex">头衔颜色（Hex，可选）</Label>
    <input id="forum_flair_color_hex" v-model="bioForm.user.forum_flair_color_hex" class="h-9 w-full rounded-md border px-2 text-sm" placeholder="#6366f1" />
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

  <div v-if="profile.forum_signature && !editingSignature" class="mb-6 max-w-xl rounded-lg border p-4 text-sm whitespace-pre-wrap text-muted-foreground">
    签名：{{ profile.forum_signature }}
  </div>

  <form v-if="editingSignature" class="mb-6 max-w-xl space-y-3 rounded-lg border p-4" @submit.prevent="saveBio">
    <Label for="forum_signature">帖子签名（支持 Markdown）</Label>
    <Textarea id="forum_signature" v-model="bioForm.user.forum_signature" rows="3" placeholder="显示在帖子底部的签名…" />
    <div class="flex gap-2">
      <Button type="submit" size="sm" :disabled="bioForm.processing">保存</Button>
      <Button type="button" size="sm" variant="outline" @click="editingSignature = false">取消</Button>
    </div>
  </form>

  <div class="mb-4 flex gap-2">
    <Button :variant="activeTab === 'topics' ? 'default' : 'outline'" size="sm" @click="switchTab('topics')">
      主题 ({{ profile.topics_count }})
    </Button>
    <Button :variant="activeTab === 'posts' ? 'default' : 'outline'" size="sm" @click="switchTab('posts')">
      回复 ({{ profile.posts_count }})
    </Button>
    <Button :variant="activeTab === 'store' ? 'default' : 'outline'" size="sm" @click="switchTab('store')">
      商城 ({{ profile.orders_count ?? 0 }})
    </Button>
  </div>

  <section v-if="activeTab === 'topics'">
  <h2 class="mb-3 text-sm font-semibold">最近主题</h2>
  <TopicListTable v-if="topics.length" :topics="topics" show-views show-participants />
  <p v-else class="text-sm text-muted-foreground">暂无主题。</p>
  <Pagination
    v-if="topicsPagination.pages > 1"
    :pagination="topicsPagination"
    :base-path="profile.profile_url"
    page-param="topics_page"
  />
  </section>

  <section v-else-if="activeTab === 'store'">
    <h2 class="mb-3 text-sm font-semibold">我的订单</h2>
    <div v-if="store_orders?.length" class="mb-6 space-y-2 rounded-lg border p-4">
      <div v-for="order in store_orders" :key="order.order_number" class="flex flex-wrap items-center justify-between gap-2 text-sm">
        <Link :href="order.url" class="font-medium hover:underline">{{ order.order_number }}</Link>
        <span class="text-muted-foreground">{{ order.status_label }} · {{ order.total_label }}</span>
        <span class="text-xs text-muted-foreground">{{ order.created_at }}</span>
      </div>
    </div>
    <p v-else-if="profile.can_edit" class="mb-6 text-sm text-muted-foreground">暂无订单记录。</p>

    <h2 class="mb-3 text-sm font-semibold">商城评价</h2>
    <div v-if="store_reviews?.length" class="space-y-2 rounded-lg border p-4">
      <div v-for="review in store_reviews" :key="review.id" class="text-sm">
        <Link :href="review.product_url" class="font-medium hover:underline">{{ review.product_name }}</Link>
        <span class="ml-2 text-amber-500">{{ '★'.repeat(review.rating) }}</span>
        <p v-if="review.body" class="text-muted-foreground">{{ review.body }}</p>
        <p class="text-xs text-muted-foreground">{{ review.created_at }}</p>
      </div>
    </div>
    <p v-else class="text-sm text-muted-foreground">暂无商城评价。</p>
  </section>

  <section v-else>
  <h2 class="mb-3 text-sm font-semibold">最近回复</h2>
  <div v-if="recent_posts.length" class="space-y-2 rounded-lg border p-4">
    <div v-for="post in recent_posts" :key="post.id" class="text-sm">
      <Link :href="post.topic_url" class="font-medium hover:underline">#{{ post.floor_number }} {{ post.topic_title }}</Link>
      <p class="text-muted-foreground">{{ post.body }}</p>
      <p class="text-xs text-muted-foreground">{{ post.created_at }}</p>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无回复。</p>
  <Pagination
    v-if="postsPagination.pages > 1"
    :pagination="postsPagination"
    :base-path="profile.profile_url"
    page-param="posts_page"
  />
  </section>

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
