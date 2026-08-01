<script setup lang="ts">
import { computed, ref } from 'vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'

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
      preserveScroll: false,
      onFinish: () => {
        switching.value = null
      },
    },
  )
}
</script>

<template>
  <template v-if="developerMode.enabled">
    <div
      aria-hidden="true"
      class="pointer-events-none fixed inset-0 z-[90] flex items-center justify-center overflow-hidden"
    >
      <span
        class="-rotate-12 select-none text-6xl font-black tracking-[0.18em] text-amber-500 opacity-[0.055] md:text-8xl"
      >
        {{ t('common.developerModeBadge') }}
      </span>
    </div>

    <div
      v-if="developerMode.tools_access"
      class="fixed bottom-4 right-4 z-[95]"
    >
      <button
        type="button"
        class="rounded-full border border-amber-500/50 bg-amber-100 px-4 py-2 text-sm font-semibold text-amber-950 shadow-lg hover:bg-amber-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500"
        :aria-expanded="open"
        @click="open = !open"
      >
        {{ t('common.developerPersonas') }}
      </button>
      <div
        v-if="open"
        class="mt-2 w-56 rounded-xl border border-amber-500/30 bg-background p-3 shadow-xl"
      >
        <p class="mb-2 text-xs text-muted-foreground">
          {{ t('common.developerCurrentPersona') }}
          {{ t(`common.developerPersona.${developerMode.current_persona ?? 'operator'}`) }}
        </p>
        <div class="grid gap-2">
          <button
            v-for="persona in developerMode.personas ?? []"
            :key="persona.key"
            type="button"
            class="rounded-lg border border-border px-3 py-2 text-left text-sm hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="!persona.available || switching !== null"
            @click="switchPersona(persona)"
          >
            {{ t(`common.developerPersona.${persona.key}`) }}
          </button>
        </div>
      </div>
    </div>
  </template>
</template>
