# Forum Extension reference plugin

This installable CE plugin demonstrates namespaced topic metadata, a granular
moderation permission, a UI action targeted at the existing report workbench,
translations, and a plugin-owned review event. It does not patch core models or
ship custom frontend code.

```sh
bin/mcweb-plugin test examples/plugins/forum-extension --json
bin/mcweb-plugin build examples/plugins/forum-extension --json
```
