---
title: Website CMS
description: 管理官网首页区块、页面、文章、翻译、修订和站点地图。
edition: ce
audience:
  - administrator
  - staff
---

McWeb's website module provides block-based pages, blog articles, navigation, and themes for the public marketing site.

## Architecture

| Layer | Technology |
|-------|------------|
| Public site | Inertia + `WebsiteLayout.vue` |
| Admin | `/admin/website/*` Inertia pages |
| ZIP templates | `/admin/frontend/templates` (portal/store skin) — separate from `Website::Theme` |

## Homepage

When a **published** page with `page_type=home` exists, `/` renders its blocks (same as `Website/Pages/Show.vue`). Otherwise `/` falls back to the marketing `Website/Home.vue`.

If CMS home is active, `/home` redirects to `/`.

## Block types

| Type | Settings |
|------|----------|
| `hero` | headline, subheadline, cta_text, cta_url |
| `rich_text` | html (sanitized on output) |

Manage blocks in **Admin → Website → Pages → Edit → Blocks** tab.

## Articles

Articles support Markdown `body` (rendered via `Community::FormatPostBody`), `summary`, SEO, and translations. Public URL: `/blog/:slug`.

## Permissions

| Permission | Access |
|------------|--------|
| `website.pages.read` | List/show pages, articles, nav, themes |
| `website.pages.edit` | Create/update/delete pages, blocks, nav, themes |
| `website.pages.publish` | Publish/schedule pages |
| `website.articles.read` | List/show articles |
| `website.articles.edit` | Edit articles |
| `website.articles.publish` | Publish/schedule articles |

## Translations JSON

Stored on pages/articles/blocks under `translations`:

```json
{
  "en": { "title": "...", "seo": { "title": "...", "description": "..." } },
  "zh-CN": { "title": "...", "seo": { "description": "..." } }
}
```

Public SEO resolves locale via `Website::ResolveSeo`.

## Scheduled publish

`Website::PublishScheduledContentJob` runs every 5 minutes (Sidekiq cron) and publishes pages/articles where `status=scheduled` and `scheduled_at <= now`.

## Revisions

Publishing a page creates a `Website::PageRevision` snapshot. View history on the page admin show → Revisions. **Restore as draft** copies snapshot into a new draft page.

## Sitemap

`Website::GenerateSitemapJob` writes `public/sitemap.xml` with `/`, `/blog`, page slugs, and `/blog/:slug` article URLs.

## ZIP templates

Open **Admin → Website → Frontend templates** to upload, activate, preview or remove portal and
website template packages. The page links to the current manifest specification and a downloadable
starter package. A package must be a ZIP whose manifest declares its supported scopes; inspect the
reported checksum and status before activation. Removing a non-built-in package does not change the
built-in fallback.
