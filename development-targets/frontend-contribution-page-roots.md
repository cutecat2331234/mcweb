# Frontend contribution page roots

## Ownership

- **Owner:** CE.
- **Why:** downstream editions keep owned Vue pages in their own repository-layer directories. Safely mapping those physical files to canonical Inertia component names is a generic extension primitive, not Channel or PVP behavior.

## Requirements

1. Every executable contribution declares the repository page roots from which it may load Vue pages. The default remains `app/javascript/pages` for compatibility.
2. A page root must be `app/javascript/pages` or a descendant edition prefix ending in `/app/javascript/pages`; absolute paths, traversal, and arbitrary source roots are rejected.
3. The adapter accepts a loader only when its physical path belongs to a declared root and its canonical component is owned by that same contribution.
4. Physical edition directories are erased from the Inertia lookup key: `ee/app/javascript/pages/Ee/EnterpriseShell.vue` resolves only as `Ee/EnterpriseShell`.
5. A contribution cannot use a broad root declaration to load base or sibling pages because component ownership remains an independent required check.

## Tasks

- [x] Add `page_roots` to the manifest schema and Ruby/TypeScript registries.
- [x] Default existing contributions to the CE page root.
- [x] Make executable adapter page canonicalization use only the contribution's declared roots.
- [x] Preserve the canonical `../pages/<component>.vue` resolver key.
- [x] Add a static contract for the downstream-root seam.
- [ ] Declare `ee/app/javascript/pages` in the EE Channel/Staff/Admin Chat adapters after ordinary inheritance.

## Acceptance

- An EE loader below `ee/app/javascript/pages` is accepted only when that exact root is declared.
- An undeclared edition root, traversal path, non-Vue file, or page owned by another contribution fails closed.
- CE and EE-PVP root-owned pages keep their existing canonical component names.
