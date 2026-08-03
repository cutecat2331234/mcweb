<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Alert from '@/components/ui/Alert.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'
import { csrfHeaders, readCsrfToken } from '@/lib/csrf'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  verification_error?: string
}>()

const page = usePage()
const { t } = useI18n()
const form = useForm({
  two_factor: {
    code: '',
  },
})

const verificationError = computed(() => {
  if (form.errors.base) return form.errors.base
  if (props.verification_error) return props.verification_error
  const pageErrors = page.props.errors as Record<string, string> | undefined
  return pageErrors?.base || ''
})

function submit() {
  const token = String(page.props.csrf_token || readCsrfToken())
  form
    .transform((data) => ({ ...data, authenticity_token: token }))
    .post(routes.identitySessionTwoFactor, {
      preserveScroll: true,
      headers: csrfHeaders(),
    })
}
</script>

<template>
  <PageHeader :title="t('auth.twoFactor.title')" :subtitle="t('auth.twoFactor.subtitle')" />

  <Alert
    v-if="verificationError"
    variant="destructive"
    :title="t('auth.twoFactor.failed')"
    class="mb-4 max-w-md"
  >
    {{ verificationError }}
  </Alert>

  <form
    class="max-w-md space-y-4"
    method="post"
    :action="routes.identitySessionTwoFactor"
    @submit.prevent="submit"
  >
    <input type="hidden" name="authenticity_token" :value="String(page.props.csrf_token || readCsrfToken())" />
    <div class="space-y-2">
      <Label for="two_factor_code">{{ t('auth.twoFactor.code') }}</Label>
      <Input
        id="two_factor_code"
        v-model="form.two_factor.code"
        name="two_factor[code]"
        type="text"
        autocomplete="one-time-code"
        autocapitalize="characters"
        spellcheck="false"
        required
        autofocus
      />
    </div>

    <div class="flex flex-wrap items-center justify-between gap-3 pt-2">
      <Button type="submit" :disabled="form.processing">
        {{ t('auth.twoFactor.verify') }}
      </Button>
      <div class="flex flex-col items-end gap-1 text-sm">
        <Link :href="routes.signIn" class="text-muted-foreground hover:text-foreground">
          {{ t('auth.twoFactor.backToSignIn') }}
        </Link>
        <Link :href="routes.totpRecoveryRequest" class="text-muted-foreground hover:text-foreground">
          {{ t('auth.twoFactor.recover') }}
        </Link>
      </div>
    </div>
  </form>
</template>
