<script setup lang="ts">
import { computed, type Component } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Avatar,
  Button,
  Card,
  Descriptions,
  DescriptionsItem,
  Grid,
  GridItem,
  Link as ArcoLink,
  PageHeader,
  Space,
  Statistic,
  Tag,
  TypographyParagraph,
  TypographyText,
  TypographyTitle,
} from '@mcweb/ui'
import {
  IconCloud,
  IconEdit,
  IconLock,
  IconMessage,
  IconNotification,
  IconUserGroup,
} from '@arco-design/web-vue/es/icon'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

type DashboardDestination = {
  key: string
  href: string
  icon: Component
}

type ForumDestination = Pick<DashboardDestination, 'key' | 'href'>

type ForumToolGroup = {
  key: 'content' | 'moreCommunity' | 'privacy'
  items: ForumDestination[]
}

const props = defineProps<{
  identity: {
    avatar_url: string
    display_name: string | null
    username: string
    email: string
    locale: string
    joined_at: string
  }
  security: {
    email_verified: boolean
    totp_enabled: boolean
    require_totp: boolean
    active_sessions_count: number
  }
  activity: {
    unread_notifications: number
    unread_messages: number | null
    topic_drafts: number | null
  }
  minecraft: {
    bound: boolean
    username?: string | null
    uuid?: string | null
  } | null
  forum_enabled: boolean
  minecraft_enabled: boolean
}>()

const { locale, t } = useI18n()

const displayName = computed(() => props.identity.display_name || props.identity.username)

const activityItems = computed(() => {
  const items: Array<DashboardDestination & { value: number }> = [{
    key: 'notifications',
    value: props.activity.unread_notifications,
    href: routes.accountNotifications,
    icon: IconNotification,
  }]
  if (props.forum_enabled) {
    items.push(
      {
        key: 'messages',
        value: props.activity.unread_messages ?? 0,
        href: routes.forumMessages,
        icon: IconMessage,
      },
      {
        key: 'drafts',
        value: props.activity.topic_drafts ?? 0,
        href: routes.forumDrafts,
        icon: IconEdit,
      },
    )
  }
  return items
})

const accountActions: DashboardDestination[] = [
  { key: 'sessions', href: routes.sessionsManagement, icon: IconUserGroup },
  { key: 'dataExports', href: routes.identityDataExports, icon: IconCloud },
]

const forumToolGroups: ForumToolGroup[] = [
  {
    key: 'content',
    items: [
      { key: 'newTopics', href: routes.forumNew },
      { key: 'unread', href: routes.forumUnread },
    ],
  },
  {
    key: 'moreCommunity',
    items: [
      { key: 'watching', href: routes.forumWatching },
      { key: 'watchedTags', href: routes.forumWatchedTags },
      { key: 'bookmarks', href: routes.forumBookmarks },
      { key: 'muted', href: routes.forumMuted },
    ],
  },
  {
    key: 'privacy',
    items: [
      { key: 'following', href: routes.forumFollowing },
      { key: 'blocks', href: routes.forumBlocks },
      { key: 'ignores', href: routes.forumIgnores },
    ],
  },
]

function visit(href: string) {
  router.visit(href)
}

function formatJoinedAt(value: string) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium' }).format(new Date(value))
}
</script>

<template>
  <Space direction="vertical" fill size="large">
    <PageHeader
      :show-back="false"
      :title="t('accountCenter.title')"
      :subtitle="t('accountCenter.subtitle')"
    />

    <Grid :cols="{ xs: 1, lg: 3 }" :col-gap="16" :row-gap="16">
      <GridItem :span="{ xs: 1, lg: 2 }">
        <Card :bordered="true">
          <Space direction="vertical" fill size="large">
            <Space align="center" size="large" wrap>
              <Avatar :size="72" :image-url="identity.avatar_url">
                {{ identity.username.slice(0, 1).toUpperCase() }}
              </Avatar>
              <Space direction="vertical" :size="2">
                <TypographyTitle :heading="3" class="!m-0">
                  {{ displayName }}
                </TypographyTitle>
                <TypographyText type="secondary">@{{ identity.username }}</TypographyText>
                <TypographyText type="secondary">{{ identity.email }}</TypographyText>
              </Space>
            </Space>

            <Button type="primary" @click="visit(routes.identityProfile)">
              <template #icon><IconEdit /></template>
              {{ t('accountCenter.actions.profile') }}
            </Button>
          </Space>
        </Card>
      </GridItem>

      <GridItem :span="{ xs: 1, lg: 1 }">
        <Card :title="t('accountCenter.security.title')" :bordered="true">
          <Descriptions :column="1" size="medium">
            <DescriptionsItem :label="t('accountCenter.security.email')">
              <Tag :color="security.email_verified ? 'green' : 'orange'">
                {{ t(security.email_verified ? 'accountCenter.status.verified' : 'accountCenter.status.unverified') }}
              </Tag>
            </DescriptionsItem>
            <DescriptionsItem :label="t('accountCenter.security.twoFactor')">
              <Tag :color="security.totp_enabled ? 'green' : (security.require_totp ? 'red' : 'gray')">
                {{ t(security.totp_enabled ? 'accountCenter.status.enabled' : 'accountCenter.status.disabled') }}
              </Tag>
            </DescriptionsItem>
            <DescriptionsItem :label="t('accountCenter.security.sessions')">
              {{ security.active_sessions_count }}
            </DescriptionsItem>
          </Descriptions>
          <template #actions>
            <Button type="text" @click="visit(routes.securityPassword)">
              <template #icon><IconLock /></template>
              {{ t('accountCenter.actions.password') }}
            </Button>
            <Button type="text" @click="visit(routes.security)">
              {{ t('accountCenter.security.review') }}
            </Button>
          </template>
        </Card>
      </GridItem>
    </Grid>

    <Card :title="t('accountCenter.activity.title')" :bordered="true">
      <Grid :cols="{ xs: 1, sm: forum_enabled ? 3 : 1 }" :col-gap="16" :row-gap="16">
        <GridItem v-for="item in activityItems" :key="item.key">
          <Space direction="vertical" fill>
            <Space align="center">
              <component :is="item.icon" />
              <Statistic
                :title="t(`accountCenter.activity.${item.key}`)"
                :value="item.value"
              />
            </Space>
            <Button
              type="text"
              size="small"
              :aria-label="t('accountCenter.openItem', { item: t(`accountCenter.activity.${item.key}`) })"
              @click="visit(item.href)"
            >
              {{ t('accountCenter.activity.open') }}
            </Button>
          </Space>
        </GridItem>
      </Grid>
    </Card>

    <Grid :cols="{ xs: 1, lg: minecraft_enabled ? 3 : 2 }" :col-gap="16" :row-gap="16">
      <GridItem v-if="minecraft_enabled">
        <Card :title="t('accountCenter.minecraft.title')" :bordered="true">
          <template v-if="minecraft?.bound">
            <TypographyTitle :heading="5" class="!m-0">
              {{ minecraft.username || t('common.notAvailable') }}
            </TypographyTitle>
            <TypographyParagraph type="secondary" class="break-all">
              {{ minecraft.uuid || t('common.notAvailable') }}
            </TypographyParagraph>
          </template>
          <TypographyParagraph v-else type="secondary">
            {{ t('accountCenter.minecraft.unbound') }}
          </TypographyParagraph>
          <Button type="secondary" @click="visit(routes.minecraftLink)">
            {{ t(minecraft?.bound ? 'accountCenter.minecraft.manage' : 'accountCenter.minecraft.bind') }}
          </Button>
        </Card>
      </GridItem>

      <GridItem>
        <Card :title="t('accountCenter.identity.title')" :bordered="true">
          <Descriptions :column="1" size="medium">
            <DescriptionsItem :label="t('accountCenter.identity.username')">
              {{ identity.username }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('accountCenter.identity.language')">
              {{ t(`locale.${identity.locale}`) }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('accountCenter.identity.joinedAt')">
              {{ formatJoinedAt(identity.joined_at) }}
            </DescriptionsItem>
          </Descriptions>
        </Card>
      </GridItem>

      <GridItem>
        <Card :title="t('accountCenter.groups.account')" :bordered="true">
          <Space direction="vertical" fill size="large">
            <Space
              v-for="action in accountActions"
              :key="action.key"
              align="center"
              class="justify-between"
              fill
              wrap
            >
              <Space align="center">
                <component :is="action.icon" />
                <Space direction="vertical" :size="0">
                  <TypographyText>{{ t(`accountCenter.items.${action.key}.title`) }}</TypographyText>
                  <TypographyText type="secondary">
                    {{ t(`accountCenter.items.${action.key}.description`) }}
                  </TypographyText>
                </Space>
              </Space>
              <Button
                type="text"
                :aria-label="t('accountCenter.openItem', { item: t(`accountCenter.items.${action.key}.title`) })"
                @click="visit(action.href)"
              >
                {{ t('accountCenter.open') }}
              </Button>
            </Space>
          </Space>
        </Card>
      </GridItem>
    </Grid>

    <Card
      v-if="forum_enabled"
      :title="t('accountCenter.groups.community')"
      :bordered="true"
    >
      <Descriptions :column="1" size="medium">
        <DescriptionsItem
          v-for="group in forumToolGroups"
          :key="group.key"
          :label="t(`accountCenter.groups.${group.key}`)"
        >
          <Space wrap>
            <ArcoLink
              v-for="item in group.items"
              :key="item.key"
              :href="item.href"
            >
              {{ t(`accountCenter.items.${item.key}.title`) }}
            </ArcoLink>
          </Space>
        </DescriptionsItem>
      </Descriptions>
    </Card>
  </Space>
</template>
