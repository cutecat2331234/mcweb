---
title: First-run configuration
description: Verify the site, administrator, jobs, email, storage, backups, and integrations after installing McWeb CE.
edition: ce
audience:
  - administrator
  - operator
sidebar:
  order: 2
---

Start after installation has completed and the site answers HTTP requests.

1. Open the public site and administration area and check that static assets load.
2. Sign in with the installation administrator and verify that server-side permissions match the assigned role.
3. Check database, cache, and background worker health.
4. Send a test email and verify the public URL, sender, and callback addresses.
5. Enable two-factor authentication for administrators and store recovery codes offline.
6. Create a backup before importing production data, then restore it in an isolated environment.

Configure attachment scanning and payment providers before enabling those public workflows. Never reuse development credentials in production.
