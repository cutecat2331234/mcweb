<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import Button from '@/components/ui/Button.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import FileInput from '@/components/ui/FileInput.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import MinecraftProfileCard, { type MinecraftProfile } from '@/components/minecraft/MinecraftProfileCard.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
    assigned_count?: number
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
    store_credit_label?: string | null
    store_wallet_url?: string | null
  }
  warnings?: Array<{
    reason: string
    points: number
    issuer: string
    created_at: string
  }>
  topics: TopicListItem[]
  topicsPagination: PaginationMeta
  assigned_topics?: TopicListItem[]
  assignedPagination?: PaginationMeta
  recent_posts: Array<{
    id: number
    body: string
    floor_number: number
    topic_title: string
    topic_url: string
    created_at: string
  }>
  postsPagination: PaginationMeta
  activeTab: 'topics' | 'posts' | 'store' | 'assigned' | 'minecraft'
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
    slug?: string
    icon: string
    description: string | null
    color: string
    granted_at?: string
    url?: string
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
  account_type?: string | null
  role_names?: string[]
  game_permission_groups?: Array<{ key: string; label: string; source: string }>
  minecraft?: MinecraftProfile
  skin_mode?: string
  profile_sections?: string[]
}>()

const profileSections = computed(() => props.profile_sections?.length
  ? props.profile_sections
  : [ 'minecraft', 'trust', 'roles', 'game_groups' ])

type ProfileEditPanel = 'title' | 'bio' | 'signature' | null
const profileEditPanel = ref<ProfileEditPanel>(null)
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

function toggleProfileEdit(panel: ProfileEditPanel) {
  profileEditPanel.value = profileEditPanel.value === panel ? null : panel
}

function saveBio() {
  bioForm.patch(`/app/forum/users/${props.profile.username}`, {
    preserveScroll: true,
    onSuccess: () => {
      profileEditPanel.value = null
    },
  })
}

function removeAvatar() {
  router.post(`/app/forum/users/${props.profile.username}`, {
    _method: 'patch',
    user: { remove_forum_avatar: true },
  }, { preserveScroll: true })
}

function uploadAvatar(file: File) {
  const data = new FormData()
  data.append('_method', 'patch')
  data.append('user[forum_avatar]', file)
  router.post(`/app/forum/users/${props.profile.username}`, data, {
    forceFormData: true,
    preserveScroll: true,
  })
}

function switchTab(tab: 'topics' | 'posts' | 'store' | 'assigned' | 'minecraft') {
  router.get(routes.forumUser(props.profile.username), { tab }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: profile.username, current: true },
  ]" />

  <p v-if="profile.mute_info" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    {{ t('userProfile.mutedWithInfo', {
      section: profile.mute_info.section,
      reasonPart: profile.mute_info.reason ? t('userProfile.muteReasonPart', { reason: profile.mute_info.reason }) : '',
      expires: profile.mute_info.expires_at,
    }) }}
  </p>
  <p v-else-if="profile.is_muted" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    {{ t('userProfile.mutedGeneric') }}
  </p>

  <section class="mb-8 overflow-hidden rounded-xl border bg-card">
    <div class="flex flex-col gap-6 p-6 lg:flex-row lg:items-start">
      <img
        :src="profile.avatar_url"
        :alt="profile.username"
        class="mx-auto h-24 w-24 shrink-0 rounded-full ring-2 ring-border lg:mx-0"
      />

      <div class="min-w-0 flex-1 space-y-4">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
          <div class="min-w-0 space-y-2 text-center lg:text-left">
            <div class="flex flex-wrap items-center justify-center gap-2 lg:justify-start">
              <h1 class="text-2xl font-bold tracking-tight sm:text-3xl">
                {{ profile.display_name || profile.username }}
              </h1>
              <span
                v-if="profile.forum_title"
                class="rounded-full border px-2 py-0.5 text-xs font-medium"
                :style="profile.forum_flair_color_hex ? { borderColor: profile.forum_flair_color_hex, color: profile.forum_flair_color_hex } : undefined"
              >
                {{ profile.forum_title }}
              </span>
            </div>
            <p class="text-sm text-muted-foreground">
              @{{ profile.username }} · {{ t('userProfile.joinedAt') }} {{ profile.member_since }}
              <span v-if="profile.last_seen_at"> · {{ t('userProfile.lastSeen') }} {{ profile.last_seen_at }}</span>
              <span v-if="profile.online"> · {{ t('userProfile.online') }}</span>
              · {{ profile.trust_name }} (Lv.{{ profile.trust_level }})
            </p>
            <div class="flex flex-wrap justify-center gap-x-5 gap-y-2 text-sm lg:justify-start">
              <span><strong>{{ profile.topics_count }}</strong> {{ t('userProfile.topics') }}</span>
              <span><strong>{{ profile.posts_count }}</strong> {{ t('userProfile.posts') }}</span>
              <span v-if="profile.orders_count"><strong>{{ profile.orders_count }}</strong> {{ t('userProfile.orders') }}</span>
              <Link v-if="profile.followers_url" :href="profile.followers_url" class="hover:underline">
                <strong>{{ profile.followers_count ?? 0 }}</strong> {{ t('userProfile.followers') }}
              </Link>
              <span><strong>{{ profile.likes_received }}</strong> {{ t('userProfile.likesReceived') }}</span>
              <span v-if="profile.warning_points != null"><strong>{{ profile.warning_points }}</strong> {{ t('userProfile.warningPoints') }}</span>
              <span v-if="profile.store_credit_label">
                {{ t('userProfile.storeCredit') }} <strong>{{ profile.store_credit_label }}</strong>
                <Link v-if="profile.store_wallet_url" :href="profile.store_wallet_url" class="ml-1 text-primary hover:underline">{{ t('userProfile.wallet') }}</Link>
              </span>
            </div>
          </div>

          <div class="flex flex-wrap justify-center gap-2 lg:justify-end">
            <Button v-if="profile.message_url" as-child size="sm">
              <Link :href="profile.message_url">{{ t('userProfile.sendMessage') }}</Link>
            </Button>
            <Button
              v-if="profile.follow_url"
              type="button"
              size="sm"
              :variant="profile.is_following ? 'outline' : 'default'"
              @click="toggleFollow"
            >
              {{ profile.is_following ? t('userProfile.unfollow') : t('userProfile.follow') }}
            </Button>
            <Button
              v-if="profile.block_url"
              type="button"
              size="sm"
              :variant="profile.is_blocked ? 'outline' : 'destructive'"
              @click="toggleBlock"
            >
              {{ profile.is_blocked ? t('userProfile.unblock') : t('userProfile.block') }}
            </Button>
            <Button
              v-if="profile.ignore_url"
              type="button"
              size="sm"
              :variant="profile.is_ignored ? 'outline' : 'secondary'"
              @click="toggleIgnore"
            >
              {{ profile.is_ignored ? t('userProfile.unignore') : t('userProfile.ignore') }}
            </Button>
            <Button v-if="profile.can_edit" type="button" size="sm" variant="outline" @click="toggleProfileEdit('title')">
              {{ profileEditPanel === 'title' ? t('userProfile.collapseTitle') : t('userProfile.editTitle') }}
            </Button>
            <Button v-if="profile.can_edit" type="button" size="sm" variant="outline" @click="toggleProfileEdit('bio')">
              {{ profileEditPanel === 'bio' ? t('userProfile.collapseBio') : t('userProfile.editBio') }}
            </Button>
            <Button v-if="profile.can_edit" type="button" size="sm" variant="outline" @click="toggleProfileEdit('signature')">
              {{ profileEditPanel === 'signature' ? t('userProfile.collapseSignature') : t('userProfile.editSignature') }}
            </Button>
            <template v-if="profile.can_edit">
              <FileInput accept="image/*" :button-label="t('userProfile.changeAvatar')" @change="uploadAvatar" />
              <Button type="button" size="sm" variant="outline" @click="removeAvatar">{{ t('userProfile.resetAvatar') }}</Button>
            </template>
          </div>
        </div>

        <div v-if="warnings?.length" class="max-w-xl rounded-lg border p-4">
          <h3 class="mb-2 text-sm font-semibold">{{ t('userProfile.warningsTitle') }}</h3>
          <ul class="space-y-2 text-sm">
            <li v-for="(warning, index) in warnings" :key="index" class="flex justify-between gap-4 border-b pb-2 last:border-0 last:pb-0">
              <span>{{ warning.reason }}</span>
              <span class="shrink-0 text-muted-foreground">{{ warning.points }} {{ t('userProfile.warningPointsUnit') }} · {{ warning.issuer }} · {{ warning.created_at }}</span>
            </li>
          </ul>
        </div>

        <template v-for="section in profileSections" :key="section">
          <div v-if="section === 'trust' && profile.trust_progress" class="max-w-md rounded-lg border p-3 text-sm">
            <p class="font-medium">{{ t('userProfile.trustLevel') }} · {{ profile.trust_progress.name }} (Lv.{{ profile.trust_progress.level }})</p>
            <p v-if="profile.trust_progress.posts_needed > 0" class="mt-1 text-muted-foreground">
              {{ t('userProfile.trustPostsNeeded', { count: profile.trust_progress.posts_needed, next: profile.trust_progress.next_level_name }) }}
            </p>
            <p v-else class="mt-1 text-muted-foreground">{{ t('userProfile.trustMaxLevel') }}</p>
          </div>

          <div v-else-if="section === 'account_type' && account_type" class="max-w-md rounded-lg border p-3 text-sm">
            <p class="font-medium">{{ t('userProfile.accountType') }}</p>
            <p class="mt-1"><Badge variant="outline">{{ account_type }}</Badge></p>
          </div>

          <div v-else-if="section === 'roles' && role_names?.length" class="max-w-md rounded-lg border p-3 text-sm">
            <p class="mb-2 font-medium">{{ t('userProfile.websiteRoles') }}</p>
            <div class="flex flex-wrap gap-2">
              <Badge v-for="role in role_names" :key="role" variant="secondary">{{ role }}</Badge>
            </div>
          </div>

          <div v-else-if="section === 'game_groups' && game_permission_groups?.length" class="max-w-md rounded-lg border p-3 text-sm">
            <p class="mb-2 font-medium">{{ t('userProfile.gameGroups') }}</p>
            <div class="flex flex-wrap gap-2">
              <Badge v-for="group in game_permission_groups" :key="group.key" variant="outline">
                {{ group.label }} <span class="text-muted-foreground">({{ group.source }})</span>
              </Badge>
            </div>
          </div>

          <MinecraftProfileCard
            v-else-if="section === 'minecraft' && minecraft && activeTab !== 'minecraft'"
            :minecraft="minecraft"
            :skin-mode="skin_mode"
            class="max-w-xl"
          />
        </template>

        <div v-if="badges.length" class="flex flex-wrap justify-center gap-2 lg:justify-start">
          <Link
            v-for="badge in badges"
            :key="badge.slug || badge.name"
            :href="badge.url || routes.forumBadges"
            class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs hover:bg-muted/50"
            :style="{ borderColor: badge.color, color: badge.color }"
            :title="badge.description ? `${badge.description} · ${badge.granted_at}` : badge.granted_at"
          >
            {{ badge.icon }} {{ badge.name }}
            <span v-if="badge.granted_at" class="text-[10px] opacity-70">{{ badge.granted_at }}</span>
          </Link>
        </div>
      </div>
    </div>
  </section>

  <form v-if="profileEditPanel === 'title'" class="mb-6 max-w-xl space-y-3 rounded-lg border p-4" @submit.prevent="saveBio">
    <Label for="forum_title">{{ t('userProfile.forumTitle') }}</Label>
    <Input id="forum_title" v-model="bioForm.user.forum_title" :placeholder="t('userProfile.forumTitlePlaceholder')" />
    <Label for="forum_flair_color_hex">{{ t('userProfile.flairColor') }}</Label>
    <Input id="forum_flair_color_hex" v-model="bioForm.user.forum_flair_color_hex" placeholder="#6366f1" />
    <div class="flex flex-wrap justify-end gap-2 sm:justify-start">
      <Button type="submit" size="sm" :disabled="bioForm.processing">{{ t('common.save') }}</Button>
      <Button type="button" size="sm" variant="outline" @click="profileEditPanel = null">{{ t('common.cancel') }}</Button>
    </div>
  </form>

  <div v-if="profile.bio && profileEditPanel !== 'bio'" class="mb-6 max-w-xl rounded-lg border p-4 text-sm whitespace-pre-wrap">
    {{ profile.bio }}
  </div>

  <form v-if="profileEditPanel === 'bio'" class="mb-6 max-w-xl space-y-3 rounded-lg border p-4" @submit.prevent="saveBio">
    <Label for="bio">{{ t('userProfile.bio') }}</Label>
    <Textarea id="bio" v-model="bioForm.user.bio" rows="4" :placeholder="t('userProfile.bioPlaceholder')" />
    <div class="flex gap-2">
      <Button type="submit" size="sm" :disabled="bioForm.processing">{{ t('common.save') }}</Button>
      <Button type="button" size="sm" variant="outline" @click="profileEditPanel = null">{{ t('common.cancel') }}</Button>
    </div>
  </form>

  <div v-if="profile.forum_signature && profileEditPanel !== 'signature'" class="mb-6 max-w-xl rounded-lg border p-4 text-sm whitespace-pre-wrap text-muted-foreground">
    {{ t('userProfile.signaturePrefix') }}{{ profile.forum_signature }}
  </div>

  <form v-if="profileEditPanel === 'signature'" class="mb-6 max-w-xl space-y-3 rounded-lg border p-4" @submit.prevent="saveBio">
    <Label for="forum_signature">{{ t('userProfile.signatureLabel') }}</Label>
    <Textarea id="forum_signature" v-model="bioForm.user.forum_signature" rows="3" :placeholder="t('userProfile.signaturePlaceholder')" />
    <div class="flex gap-2">
      <Button type="submit" size="sm" :disabled="bioForm.processing">{{ t('common.save') }}</Button>
      <Button type="button" size="sm" variant="outline" @click="profileEditPanel = null">{{ t('common.cancel') }}</Button>
    </div>
  </form>

  <div class="mb-4 flex flex-wrap justify-start gap-2">
    <Button :variant="activeTab === 'topics' ? 'default' : 'outline'" size="sm" @click="switchTab('topics')">
      {{ t('userProfile.tabTopics') }} ({{ profile.topics_count }})
    </Button>
    <Button :variant="activeTab === 'posts' ? 'default' : 'outline'" size="sm" @click="switchTab('posts')">
      {{ t('userProfile.tabPosts') }} ({{ profile.posts_count }})
    </Button>
    <Button :variant="activeTab === 'store' ? 'default' : 'outline'" size="sm" @click="switchTab('store')">
      {{ t('userProfile.tabStore') }} ({{ profile.orders_count ?? 0 }})
    </Button>
    <Button
      v-if="profile.assigned_count"
      :variant="activeTab === 'assigned' ? 'default' : 'outline'"
      size="sm"
      @click="switchTab('assigned')"
    >
      {{ t('userProfile.tabAssigned') }} ({{ profile.assigned_count }})
    </Button>
    <Button
      v-if="minecraft?.linked"
      :variant="activeTab === 'minecraft' ? 'default' : 'outline'"
      size="sm"
      @click="switchTab('minecraft')"
    >
      {{ t('userProfile.tabMinecraft') }}
    </Button>
  </div>

  <section v-if="activeTab === 'minecraft'">
    <MinecraftProfileCard
      v-if="minecraft?.linked"
      :minecraft="minecraft"
      :skin-mode="skin_mode"
      class="max-w-xl"
    />
    <p v-else class="text-sm text-muted-foreground">{{ t('userProfile.noMinecraft') }}</p>
  </section>

  <section v-if="activeTab === 'topics'">
  <h2 class="mb-3 text-sm font-semibold">{{ t('userProfile.recentTopics') }}</h2>
  <TopicListTable v-if="topics.length" :topics="topics" show-views show-participants />
  <p v-else class="text-sm text-muted-foreground">{{ t('userProfile.noTopics') }}</p>
  <Pagination
    v-if="topicsPagination.pages > 1"
    :pagination="topicsPagination"
    :base-path="profile.profile_url"
    page-param="topics_page"
  />
  </section>

  <section v-else-if="activeTab === 'store'">
    <h2 class="mb-3 text-sm font-semibold">{{ t('userProfile.myOrders') }}</h2>
    <div v-if="store_orders?.length" class="mb-6 space-y-2 rounded-lg border p-4">
      <div v-for="order in store_orders" :key="order.order_number" class="flex flex-wrap items-center justify-between gap-2 text-sm">
        <Link :href="order.url" class="font-medium hover:underline">{{ order.order_number }}</Link>
        <span class="text-muted-foreground">{{ order.status_label }} · {{ order.total_label }}</span>
        <span class="text-xs text-muted-foreground">{{ order.created_at }}</span>
      </div>
    </div>
    <p v-else-if="profile.can_edit" class="mb-6 text-sm text-muted-foreground">{{ t('userProfile.noOrders') }}</p>

    <h2 class="mb-3 text-sm font-semibold">{{ t('userProfile.storeReviews') }}</h2>
    <div v-if="store_reviews?.length" class="space-y-2 rounded-lg border p-4">
      <div v-for="review in store_reviews" :key="review.id" class="text-sm">
        <Link :href="review.product_url" class="font-medium hover:underline">{{ review.product_name }}</Link>
        <span class="ml-2 text-amber-500">{{ '★'.repeat(review.rating) }}</span>
        <p v-if="review.body" class="text-muted-foreground">{{ review.body }}</p>
        <p class="text-xs text-muted-foreground">{{ review.created_at }}</p>
      </div>
    </div>
    <p v-else class="text-sm text-muted-foreground">{{ t('userProfile.noStoreReviews') }}</p>
  </section>

  <section v-else-if="activeTab === 'assigned'">
    <h2 class="mb-3 text-sm font-semibold">{{ t('userProfile.assignedTopics') }}</h2>
    <TopicListTable v-if="assigned_topics?.length" :topics="assigned_topics" show-views />
    <Pagination
      v-if="assigned_topics?.length && assignedPagination"
      :pagination="assignedPagination"
      :base-path="profile.profile_url"
      page-param="assigned_page"
      :query="{ tab: 'assigned' }"
    />
    <p v-else class="text-sm text-muted-foreground">{{ t('userProfile.noAssignedTopics') }}</p>
  </section>

  <section v-else>
  <h2 class="mb-3 text-sm font-semibold">{{ t('userProfile.recentPosts') }}</h2>
  <div v-if="recent_posts.length" class="space-y-2 rounded-lg border p-4">
    <div v-for="post in recent_posts" :key="post.id" class="text-sm">
      <Link :href="post.topic_url" class="font-medium hover:underline">#{{ post.floor_number }} {{ post.topic_title }}</Link>
      <p class="text-muted-foreground">{{ post.body }}</p>
      <p class="text-xs text-muted-foreground">{{ post.created_at }}</p>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('userProfile.noRecentPosts') }}</p>
  <Pagination
    v-if="postsPagination.pages > 1"
    :pagination="postsPagination"
    :base-path="profile.profile_url"
    page-param="posts_page"
  />
  </section>

  <h2 class="mb-3 mt-8 text-sm font-semibold">{{ t('userProfile.likedPosts') }}</h2>
  <div v-if="liked_posts.length" class="space-y-2 rounded-lg border p-4">
    <div v-for="post in liked_posts" :key="post.id" class="text-sm">
      <Link :href="post.topic_url" class="font-medium hover:underline">#{{ post.floor_number }} {{ post.topic_title }}</Link>
      <span class="ml-2 text-xs text-muted-foreground">{{ t('userProfile.reactionsCount', { count: post.likes_count }) }}</span>
      <p class="text-muted-foreground">{{ post.body }}</p>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('userProfile.noLikedPosts') }}</p>
</template>
