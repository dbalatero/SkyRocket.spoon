# SkyRocket.spoon

A free clone of Coderage Software's Zooom/2 tool, written for Hammerspoon in Lua.

## Installation

The easiest thing to do is paste this in:

```
mkdir -p ~/.hammerspoon/Spoons
git clone https://github.com/dbalatero/SkyRocket.spoon.git ~/.hammerspoon/Spoons/SkyRocket.spoon
```

## Usage

Once you've installed it, add this to your `~/.hammerspoon/init.lua` file:

```lua
local SkyRocket = hs.loadSpoon("SkyRocket")

sky = SkyRocket:new({
  -- Which modifiers to hold to move a window?
  moveModifiers = {'cmd', 'shift'},

  -- Which modifiers to hold to resize a window?
  resizeModifiers = {'ctrl', 'shift'},
})
```

### Moving

To move a window, hold your `moveModifiers` down, then click and drag a window.

### Resizing

To resize a window, hold your `resizeModifiers` down, then click and drag a window.
