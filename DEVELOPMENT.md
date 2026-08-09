# DEVELOPMENT

## Product-layer ownership

McWeb is developed as an inheritance chain:

```text
CE -> EE -> EE-PVP
```

Classify every requirement before implementation. Put shared platform behavior and reusable fixes in CE; put general enterprise behavior in EE; put only PVP-specific rules and user experience in EE-PVP. If a downstream requirement reveals a reusable missing capability, implement and verify the generic capability in its highest applicable upstream layer, then merge that exact history downward.

The full project rules, including the required merge discipline, are in [AGENTS.md](AGENTS.md).
