"""The skins of the Page's landmarks (D-283): one module per landmark, drawn over the Battleground's
collision boxes and read from src/shared/Config/BattlegroundConfig.luau (page/kit.py).

Each module names its recipes in MESHES; a recipe `quill_top` is the MeshConfig key `PageQuillTop`, written
to assets/meshes/page_quill_top.glb. BattlegroundLayout.skins names the same keys from the layout, places
them, and Map draws them; the last word of a key is its tone (WorldConfig.Battleground.Skin<Tone>).
"""

from __future__ import annotations

from . import book, bridge, crater, folio, plaza, quill, scriptorium, seal

# A landmark is scenery built once, not a volume six players throw at once: its own cap, far over a glyph's.
CAP = 5000
# And its own file size: the quill's ink alone is 3,752 triangles, over the 200 KB a glyph's volume keeps to.
MAX_BYTES = 300_000

RECIPES = {
    "Page" + "".join(word.capitalize() for word in name.split("_")): (f"page_{name}.glb", getattr(module, name), CAP)
    for module in (book, quill, folio, crater, seal, scriptorium, bridge, plaza)
    for name in module.MESHES
}
