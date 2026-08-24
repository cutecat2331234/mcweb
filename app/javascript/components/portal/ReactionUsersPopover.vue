<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  Button,
  List,
  ListItem,
  Popover,
  Space,
  TypographyText,
} from '@mcweb/ui'

const { t } = useI18n()

const props = defineProps<{
  emoji: string
  count: number
  users: string[]
}>()

const open = ref(false)

function updateOpen(visible: boolean) {
  open.value = props.users.length > 0 && visible
}
</script>

<template>
  <Popover
    :popup-visible="open"
    trigger="click"
    position="top"
    @update:popup-visible="updateOpen"
  >
    <span class="inline-flex">
      <Button
        :type="open ? 'primary' : 'outline'"
        shape="round"
        size="mini"
      >
        {{ emoji }}
        <template v-if="count">{{ count }}</template>
      </Button>
    </span>
    <template #content>
      <Space direction="vertical" fill>
        <TypographyText type="secondary">
          {{ t('components.reactionUsers.title') }}
        </TypographyText>
        <List :bordered="false" size="small">
          <ListItem v-for="username in users" :key="username">
            {{ username }}
          </ListItem>
        </List>
      </Space>
    </template>
  </Popover>
</template>
