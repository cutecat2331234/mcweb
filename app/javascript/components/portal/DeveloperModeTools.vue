<script setup lang="ts">
import { computed, ref } from 'vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { IconBug } from '@arco-design/web-vue/es/icon'

interface Persona {
  key: string
  available: boolean
}

const page = usePage()
const { t } = useI18n()
const open = ref(false)
const switching = ref<string | null>(null)
const developerMode = computed(
  () =>
    (page.props.developer_mode ?? { enabled: false }) as {
      enabled: boolean
      tools_access?: boolean
      current_persona?: string
      persona_switch_url?: string
      personas?: Persona[]
    },
)

function switchPersona(persona: Persona) {
  const url = developerMode.value.persona_switch_url
  if (!url || !persona.available || switching.value) return

  switching.value = persona.key
  router.post(
    url,
    { persona: persona.key },
    {
      preserveState: false,
      preserveScroll: true,
      onFinish: () => {
        switching.value = null
      },
    },
  )
}
</script>

<template>
  <template v-if="developerMode.enabled">
    <a-back-top v-if="developerMode.tools_access" :visible-height="-1">
      <a-button
        type="primary"
        status="warning"
        shape="circle"
        :aria-label="t('common.openDeveloperTools')"
        :aria-expanded="open"
        @click.stop="open = true"
      >
        <template #icon><icon-bug /></template>
      </a-button>
    </a-back-top>

    <a-drawer
      v-model:visible="open"
      :title="t('common.developerPersonas')"
      :width="'min(380px, 100vw)'"
      :footer="false"
      unmount-on-close
    >
      <a-watermark
        :content="t('common.developerModeBadge')"
        :font="{ color: '#ff7d00', fontSize: 18, fontWeight: 700 }"
        :gap="[120, 48]"
        :alpha="0.09"
        :repeat="true"
      >
        <a-space direction="vertical" :size="16" fill>
          <a-alert
            type="warning"
            show-icon
            :title="t('common.developerMode')"
          >
            {{ t('common.developerModeWarning') }}
          </a-alert>

          <a-descriptions :column="1" bordered size="small">
            <a-descriptions-item :label="t('common.developerCurrentPersona')">
              <a-tag color="orangered">
                {{ t(`common.developerPersona.${developerMode.current_persona ?? 'operator'}`) }}
              </a-tag>
            </a-descriptions-item>
          </a-descriptions>

          <a-space direction="vertical" :size="8" fill>
            <a-button
              v-for="persona in developerMode.personas ?? []"
              :key="persona.key"
              :type="developerMode.current_persona === persona.key ? 'primary' : 'outline'"
              shape="round"
              long
              :disabled="!persona.available || switching !== null"
              :loading="switching === persona.key"
              @click="switchPersona(persona)"
            >
              {{ t(`common.developerPersona.${persona.key}`) }}
            </a-button>
          </a-space>

          <a-empty
            v-if="(developerMode.personas ?? []).length === 0"
            :description="t('common.developerPersonasEmpty')"
          />
        </a-space>
      </a-watermark>
    </a-drawer>
  </template>
</template>
