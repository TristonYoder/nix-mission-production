# Bakes a font's OpenType `zero` feature (slashed zero) into its default
# glyphs, for renderers that can't turn features on (ImageMagick).
# Usage: slashed-zero.py IN.ttf OUT.ttf
import sys
from fontTools.ttLib import TTFont

font = TTFont(sys.argv[1])
gsub = font["GSUB"].table
swap = {}
for record in gsub.FeatureList.FeatureRecord:
    if record.FeatureTag != "zero":
        continue
    for index in record.Feature.LookupListIndex:
        lookup = gsub.LookupList.Lookup[index]
        for sub in lookup.SubTable:
            if lookup.LookupType == 7:  # extension wrapper
                sub = sub.ExtSubTable
            swap.update(getattr(sub, "mapping", {}))
if not swap:
    sys.exit(f"{sys.argv[1]}: no `zero` feature")
for table in font["cmap"].tables:
    for codepoint, glyph in list(table.cmap.items()):
        if glyph in swap:
            table.cmap[codepoint] = swap[glyph]
font.save(sys.argv[2])
