# Minecraft fallback skin assets

`default-skin.png` is the official 64 x 64 wide-model Steve skin published at
`https://assets.mojang.com/SkinTemplates/steve.png`.

`default-skin-avatar.png` is generated from that skin with the same deterministic
contract as `Minecraft::SkinDerivativeBuilder`: crop the front face at `(8, 8)`
with size `8 x 8`, then resize to `128 x 128` using nearest-neighbour sampling.
It is a real Minecraft skin derivative, not a separately drawn placeholder.
