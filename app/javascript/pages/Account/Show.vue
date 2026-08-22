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
  List,
  ListItem,
  ListItemMeta,
  PageHeader,
  Space,
  Statistic,
  Tag,
  TypographyParagraph,
  TypographyText,
  TypographyTitle,
} from '@mcweb/ui'
import {
  IconBookmark,
  IconCloud,
  IconEdit,
  IconEye,
  IconEyeInvisible,
  IconLock,
  IconMessage,
  IconNotification,
  IconSettings,
  IconSubscribe,
  IconTag,
  IconTags,
  IconUserGroup,
} from '@arco-design/web-vue/es/icon'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

type DashboardAction = {
  key: string
  href: string
  icon: Component
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

const primaryActions = computed<DashboardAction[]>(() => {
  const actions: DashboardAction[] = [
    { key: 'profile', href: routes.identityProfile, icon: IconEdit },
    { key: 'password', href: routes.securityPassword, icon: IconLock },
    { key: 'security', href: routes.security, icon: IconLock },
  ]
  if (props.minecraft_enabled) {
    actions.push({ key: 'minecraft', href: routes.minecraftLink, icon: IconCloud })
  }
  return actions
})

const activityItems = computed(() => {
  const items = [{
    key: 'notifications',
    value: props.activity.unread_notifications,
    href: routes.accountNotifications,
  }]
  if (props.forum_enabled) {
    items.push(
      {
        key: 'messages',
        value: props.activity.unread_messages ?? 0,
        href: routes.forumMessages,
      },
      {
        key: 'drafts',
        value: props.activity.topic_drafts ?? 0,
        href: routes.forumDrafts,
      },
    )
  }
  return items
})

const communityActions = computed<DashboardAction[]>(() => props.forum_enabled ? [
  { key: 'newTopics', href: routes.forumNew, icon: IconNotification },
  { key: 'unread', href: routes.forumUnread, icon: IconMessage },
  { key: 'watching', href: routes.forumWatching, icon: IconSubscribe },
  { key: 'bookmarks', href: routes.forumBookmarks, icon: IconBookmark },
] : [])

const moreCommunityActions = computed<DashboardAction[]>(() => props.forum_enabled ? [
  { key: 'following', href: routes.forumFollowing, icon: IconUserGroup },
  { key: 'watchedTags', href: routes.forumWatchedTags, icon: IconTag },
  { key: 'watchedTagTopics', href: routes.forumWatchedTagTopics, icon: IconTags },
] : [])

const privacyActions = computed<DashboardAction[]>(() => props.forum_enabled ? [
  { key: 'preferences', href: routes.forumPreferences, icon: IconSettings },
  { key: 'blocks', href: routes.forumBlocks, icon: IconEyeInvisible },
  { key: 'ignores', href: routes.forumIgnores, icon: IconEye },
  { key: 'muted', href: routes.forumMuted, icon: IconNotification },
] : [])

const settingsActions = computed<DashboardAction[]>(() => {
  const actions: DashboardAction[] = [
    { key: 'sessions', href: routes.sessionsManagement, icon: IconUserGroup },
    { key: 'dataExports', href: routes.identityDataExports, icon: IconCloud },
  ]
  return actions
})

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
                <TypographyTitle :heading="3" style="margin: 0">
                  {{ displayName }}
                </TypographyTitle>
                <TypographyText type="secondary">@{{ identity.username }}</TypographyText>
                <TypographyText type="secondary">{{ identity.email }}</TypographyText>
              </Space>
            </Space>

            <Space wrap>
              <Button
                v-for="(action, index) in primaryActions"
                :key="action.key"
                :type="index === 0 ? 'primary' : 'secondary'"
                @click="visit(action.href)"
              >
                <template #icon><component :is="action.icon" /></template>
                {{ t(`accountCenter.actions.${action.key}`) }}
              </Button>
            </Space>
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
            <Button type="text" @click="visit(routes.security)">
              {{ t('accountCenter.security.review') }}
            </Button>
          </template>
        </Card>
      </GridItem>
    </Grid>

    <Card :title="t('accountCenter.activity.title')" :bordered="true">
      <Grid :cols="{ xs: 1, sm: 3 }" :col-gap="16" :row-gap="16">
        <GridItem v-for="item in activityItems" :key="item.key">
          <Space direction="vertical" fill>
            <Statistic
              :title="t(`accountCenter.activity.${item.key}`)"
              :value="item.value"
              :value-style="item.value > 0 ? { color: 'rgb(var(--orange-6))' } : undefined"
            />
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

    <Grid :cols="{ xs: 1, lg: minecraft_enabled ? 2 : 1 }" :col-gap="16" :row-gap="16">
      <GridItem v-if="minecraft_enabled">
        <Card :title="t('accountCenter.minecraft.title')" :bordered="true">
          <template v-if="minecraft?.bound">
            <TypographyTitle :heading="5" style="margin-top: 0">
              {{ minecraft.username || t('common.notAvailable') }}
            </TypographyTitle>
            <TypographyParagraph type="secondary" style="overflow-wrap: anywhere">
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
    </Grid>

    <Grid :cols="{ xs: 1, lg: forum_enabled ? 2 : 1 }" :col-gap="16" :row-gap="16">
      <GridItem v-if="forum_enabled">
        <Card :title="t('accountCenter.groups.community')" :bordered="true">
          <List :bordered="false" :split="true">
            <ListItem v-for="action in communityActions" :key="action.key">
              <template #meta>
                <ListItemMeta
                  :title="t(`accountCenter.items.${action.key}.title`)"
                  :description="t(`accountCenter.items.${action.key}.description`)"
                >
                  <template #avatar><component :is="action.icon" /></template>
                </ListItemMeta>
              </template>
              <template #actions>
                <Button
                  type="text"
                  :aria-label="t('accountCenter.openItem', { item: t(`accountCenter.items.${action.key}.title`) })"
                  @click="visit(action.href)"
                >
                  {{ t('accountCenter.open') }}
                </Button>
              </template>
            </ListItem>
          </List>
        </Card>
      </GridItem>

      <GridItem>
        <Card :title="t('accountCenter.groups.account')" :bordered="true">
          <List :bordered="false" :split="true">
            <ListItem v-for="action in settingsActions" :key="action.key">
              <template #meta>
                <ListItemMeta
                  :title="t(`accountCenter.items.${action.key}.title`)"
                  :description="t(`accountCenter.items.${action.key}.description`)"
                >
                  <template #avatar><component :is="action.icon" /></template>
                </ListItemMeta>
              </template>
              <template #actions>
                <Button
                  type="text"
                  :aria-label="t('accountCenter.openItem', { item: t(`accountCenter.items.${action.key}.title`) })"
                  @click="visit(action.href)"
                >
                  {{ t('accountCenter.open') }}
                </Button>
              </template>
            </ListItem>
          </List>
        </Card>
      </GridItem>
    </Grid>

    <Grid v-if="forum_enabled" :cols="{ xs: 1, lg: 2 }" :col-gap="16" :row-gap="16">
      <GridItem>
        <Card :title="t('accountCenter.groups.moreCommunity')" :bordered="true">
          <List :bordered="false" :split="true" size="small">
            <ListItem v-for="action in moreCommunityActions" :key="action.key">
              <template #meta>
                <ListItemMeta
                  :title="t(`accountCenter.items.${action.key}.title`)"
                  :description="t(`accountCenter.items.${action.key}.description`)"
                >
                  <template #avatar><component :is="action.icon" /></template>
                </ListItemMeta>
              </template>
              <template #actions>
                <Button
                  type="text"
                  :aria-label="t('accountCenter.openItem', { item: t(`accountCenter.items.${action.key}.title`) })"
                  @click="visit(action.href)"
                >
                  {{ t('accountCenter.open') }}
                </Button>
              </template>
            </ListItem>
          </List>
        </Card>
      </GridItem>

      <GridItem>
        <Card :title="t('accountCenter.groups.privacy')" :bordered="true">
          <List :bordered="false" :split="true" size="small">
            <ListItem v-for="action in privacyActions" :key="action.key">
              <template #meta>
                <ListItemMeta
                  :title="t(`accountCenter.items.${action.key}.title`)"
                  :description="t(`accountCenter.items.${action.key}.description`)"
                >
                  <template #avatar><component :is="action.icon" /></template>
                </ListItemMeta>
              </template>
              <template #actions>
                <Button
                  type="text"
                  :aria-label="t('accountCenter.openItem', { item: t(`accountCenter.items.${action.key}.title`) })"
                  @click="visit(action.href)"
                >
                  {{ t('accountCenter.open') }}
                </Button>
              </template>
            </ListItem>
          </List>
        </Card>
      </GridItem>
    </Grid>
  </Space>
</template>
