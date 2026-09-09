---
title: Navigation, search, and support
description: Switch between McWeb applications, open documentation, and use navigation, local search, and deep links.
edition: ce
audience:
  - user
  - staff
  - administrator
  - operator
  - plugin-developer
sidebar:
  order: 3
---

## Application navigation

The website, account, forum, store, staff workspace, and administrator area have separate page navigation while sharing the same site account. Switching applications loads the destination application; save unfinished forms before leaving.

| Address | Purpose |
| --- | --- |
| `/` | Public website |
| `/app`, `/app/account` | CE account overview; `/app` redirects here |
| `/app/account/notifications` | Unified forum, commerce, and system notifications |
| `/app/forum/latest` | Forum |
| `/app/store/products` | Store |
| `/app/staff` | Staff workspace, subject to moderation permissions |
| `/admin` | Administrator area, subject to administrator permissions |
| `/docs/` | Documentation for the installed edition |

Available application links depend on enabled features and your permissions. Personal Minecraft account management is part of the account application; managed-server operations are in the administrator area.

## Documentation and search

The public website, shared application navigation, and administrator header provide a Documentation link to `/docs/`. Documentation is a separate site section; it does not grant access to the operations it describes. Use `/docs/en/` or the documentation language selector for English.

The desktop documentation layout provides role-based navigation on the left and a page outline on the right. On small screens, open navigation from the header and use the collapsible page outline above the content.

Search uses an index shipped with the static build. Queries are not sent to a third-party search service. Copy a heading link to share a specific section, and confirm that the recipient uses the matching edition and release.

## Requesting support

When requesting help, include the McWeb edition and release, page URL, acting role, exact error text, time, a safe request identifier, and reproduction steps. Never include passwords, session cookies, API keys, webhook secrets, private keys, or credential files.
