import { defineConfig } from 'astro/config'
import starlight from '@astrojs/starlight'
import { currentEdition } from './scripts/lib/edition.mjs'

const edition = currentEdition()
const site = process.env.MCWEB_DOCS_SITE?.trim()

const sections = [
  ['开始', 'Getting started', 'getting-started'],
  ['用户指南', 'User guide', 'user'],
  ['工作人员指南', 'Staff guide', 'staff'],
  ['管理员指南', 'Administrator guide', 'admin'],
  ['运维指南', 'Operations guide', 'operations'],
  ['插件开发', 'Plugin development', 'plugin-development'],
]

export default defineConfig({
  ...(site ? { site } : {}),
  base: '/docs',
  output: 'static',
  build: {
    format: 'directory',
  },
  integrations: [
    starlight({
      title: {
        'zh-CN': `McWeb ${edition.label['zh-CN']} 文档`,
        en: `McWeb ${edition.label.en} Documentation`,
      },
      description: 'McWeb 用户、工作人员、管理员、运维与插件开发文档。',
      defaultLocale: 'root',
      locales: {
        root: { label: '简体中文', lang: 'zh-CN' },
        en: { label: 'English', lang: 'en' },
      },
      sidebar: sections.map(([label, english, directory]) => ({
        label,
        translations: { en: english },
        items: [{ autogenerate: { directory } }],
      })),
      lastUpdated: true,
      pagination: true,
      head: [
        {
          tag: 'meta',
          attrs: { name: 'mcweb-edition', content: edition.id },
        },
      ],
    }),
  ],
})
