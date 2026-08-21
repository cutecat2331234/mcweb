<script setup lang="ts">
import { computed, type Component } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Button,
  Card,
  Grid,
  GridItem,
  PageHeader,
  Space,
  TypographyText,
} from '@mcweb/ui'
import {
  IconBookmark,
  IconCloud,
  IconEye,
  IconEyeInvisible,
  IconFile,
  IconLock,
  IconMessage,
  IconNotification,
  IconPlus,
  IconSettings,
  IconSubscribe,
  IconTag,
  IconTags,
  IconUserGroup,
} from '@arco-design/web-vue/es/icon'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  forum_enabled: boolean
  minecraft_enabled: boolean
}>()

const { t } = useI18n()

type AccountItemKey =
  | 'newTopics'
  | 'unread'
  | 'watching'
  | 'following'
  | 'watchedTags'
  | 'watchedTagTopics'
  | 'bookmarks'
  | 'messages'
  | 'drafts'
  | 'preferences'
  | 'blocks'
  | 'ignores'
  | 'muted'
  | 'security'
  | 'sessions'
  | 'dataExports'
  | 'minecraft'

type AccountItem = {
  key: AccountItemKey
  href: string
  icon: Component
}

const groups = computed(() => {
  const community: AccountItem[] = props.forum_enabled ? [
    { key: 'newTopics', href: routes.forumNew, icon: IconPlus },
    { key: 'unread', href: routes.forumUnread, icon: IconNotification },
    { key: 'watching', href: routes.forumWatching, icon: IconSubscribe },
    { key: 'following', href: routes.forumFollowing, icon: IconUserGroup },
    { key: 'watchedTags', href: routes.forumWatchedTags, icon: IconTag },
    { key: 'watchedTagTopics', href: routes.forumWatchedTagTopics, icon: IconTags },
    { key: 'bookmarks', href: routes.forumBookmarks, icon: IconBookmark },
  ] : []
  const content: AccountItem[] = props.forum_enabled ? [
    { key: 'messages', href: routes.forumMessages, icon: IconMessage },
    { key: 'drafts', href: routes.forumDrafts, icon: IconFile },
  ] : []
  const account: AccountItem[] = [
    { key: 'security', href: routes.security, icon: IconLock },
    { key: 'sessions', href: routes.sessionsManagement, icon: IconUserGroup },
    { key: 'dataExports', href: routes.identityDataExports, icon: IconCloud },
  ]
  if (props.forum_enabled) {
    account.unshift(
      { key: 'preferences', href: routes.forumPreferences, icon: IconSettings },
      { key: 'blocks', href: routes.forumBlocks, icon: IconEyeInvisible },
      { key: 'ignores', href: routes.forumIgnores, icon: IconEye },
      { key: 'muted', href: routes.forumMuted, icon: IconNotification },
    )
  }
  if (props.minecraft_enabled) {
    account.push({ key: 'minecraft', href: routes.minecraftLink, icon: IconCloud })
  }

  return [
    { key: 'community', items: community },
    { key: 'content', items: content },
    { key: 'account', items: account },
  ].filter((group) => group.items.length > 0)
})

function visit(href: string) {
  router.visit(href)
}
</script>

<template>
  <Space direction="vertical" fill size="large">
    <PageHeader
      :show-back="false"
      :title="t('accountCenter.title')"
      :subtitle="t('accountCenter.subtitle')"
    />

    <Card
      v-for="group in groups"
      :key="group.key"
      :title="t(`accountCenter.groups.${group.key}`)"
      :bordered="true"
    >
      <Grid :cols="{ xs: 1, sm: 2, lg: 3 }" :col-gap="12" :row-gap="12">
        <GridItem v-for="item in group.items" :key="item.key">
          <Space direction="vertical" fill :size="4">
            <Button type="secondary" long @click="visit(item.href)">
              <template #icon><component :is="item.icon" /></template>
              {{ t(`accountCenter.items.${item.key}.title`) }}
            </Button>
            <TypographyText type="secondary">
              {{ t(`accountCenter.items.${item.key}.description`) }}
            </TypographyText>
          </Space>
        </GridItem>
      </Grid>
    </Card>
  </Space>
</template>
