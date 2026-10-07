"""Binding environment art direction; each biome owns its palette and architecture."""
ROOM_STYLE = (
    "Incense Debt game environment art: tactile Chinese folklore cut-paper stage sets, "
    "coarse woodblock contours, layered fibrous paper, hand-painted gouache pigments. "
    "Use the reference ONLY for paper texture and handmade contour quality. "
    "The environment's architecture and COLOR PALETTE must come from the individual brief below. "
    "Keep vivid distinct biome colors; no universal gray-stone temple, no universal red shrine. "
    "Near top-down 2D game perspective, consistent playable-plane scale. "
    "No lettering, no UI, no characters, no glossy 3D, no pixel art, no vector clipart. "
)


def theme(name, environment, ambient, palette, light, particles, material, architecture, variants):
    return dict(name=name, environment=environment, ambient=ambient, palette=palette,
                light_color=light, ambient_color=particles, floor_material=material,
                architecture=architecture, variants=variants)


THEMES = [
    theme("灯市后巷", "MIDNIGHT LANTERN MARKET: glowing vermilion and saturated honey amber against dark aubergine shadows",
          "ember", "lantern_amber", "#ffc05b", "#ffcf75", "reddish cherry-wood planks with pale worn seams",
          "crowded wooden shop fronts, scalloped red awnings, tightly clustered round lanterns; narrow urban silhouettes",
          ["lantern-maker lane: staggered timber stalls and round paper lamps, long plank floor",
           "festival delivery court: overhead zigzag lamp garlands and rolled awnings, herringbone timber floor"]),
    theme("纸渡河埠", "BLUE RIVER FERRY: deep indigo water, sea-teal timber and bright cyan reflections; strong cold blue identity",
          "water", "river_indigo", "#73e7f4", "#72cde5", "weathered blue-green wooden dock planks, water visible around every edge",
          "wooden piers floating on an indigo river, ferry slips, paper boats and mooring posts; no stone courtyard walls",
          ["outer ferry dock: parallel pier planks and folded ferry boats at the water rim",
           "tide terminal: cross-braced pontoon deck and curved jade water channels, dock-rope perimeter"]),
    theme("铜钱旧库", "GOLDEN COIN TREASURY: ochre gold, golden brass and dark chocolate; keep golden-yellow floor dominant",
          "coin", "treasury_gold", "#ffd66f", "#eac467", "matte golden coin-mosaic tiles with square cash motifs",
          "round bronze vault doors, stacked coin cylinders and low bullion shelves; circular treasury geometry",
          ["cash vault: square-hole coin mosaic, thick round brass arches",
           "mint workshop: burnished brass diamond floor, coin-press wheels and rounded racks at the perimeter"]),
    theme("苔庭香径", "LIVING SPRING GARDEN: bright fern green, moss lime and warm soft sunlight; luminous organic green floor",
          "leaf", "garden_lime", "#d9ef86", "#a7d46b", "living moss carpet, fern-leaf imprints and irregular ivory stepping slabs",
          "rounded hedge arches, fern planters, spreading tree roots and low woven garden gates; open-air garden without temple masonry",
          ["fern sanctuary: bright moss clearing with petal stepping stones and rounded hedge borders",
           "root courtyard: lime-green leafy floor, a curved path and flowering root arches at the rim"]),
    theme("墨雨书院", "INK RAIN ACADEMY: desaturated storm blue, slate navy and chalk white; blue-black scholarly atmosphere",
          "rain", "academy_slate", "#a3bddd", "#99b6d5", "blue-black lacquer boards with pale paper scroll inlays and loose brush-stroke patterns",
          "tall ink-stained bookcases, folded blue roof eaves, hanging blank scrolls and ink gutters; no lantern market palette",
          ["rain reading court: blue slate scroll floor with shelving bays and dripping eaves",
           "calligraphy study: pale blue-gray parchment grid floor, inkstone trays and tall brush racks at the rim"]),
    theme("赤绫戏楼", "PLUM OPERA THEATRE: saturated magenta, mulberry purple, rose silk and charcoal stage wood",
          "silk", "theatre_plum", "#ef8bdb", "#e5a0db", "polished dark plum stage boards with a dusty rose circular stage medallion",
          "layered magenta theatrical curtains, scalloped silk proscenium, carved wooden mask racks and stage wings",
          ["front stage: purple rose radial stage floor and magenta draped side wings",
           "backstage rehearsal: aubergine diagonal stage boards, rose canopy and tall folding scenery panels"]),
    theme("烛骨礼堂", "PALE WAX CHAPEL: bone ivory, cream, parchment beige and restrained amber; bright pale floor dominates",
          "wax", "chapel_cream", "#ffe1a5", "#e7cc9e", "smooth cream wax tiles with flowing drip-shaped seams",
          "melted ivory wax columns, soft rounded candle arches, low candle trays; no red cloth and no gray masonry",
          ["wax nave: pale cream long tiles, wax stalactite arches and many small amber candles",
           "candle reliquary: ivory concentric wax floor with irregular drip-edged alcoves and short wax pillars"]),
    theme("雷鼓山门", "VIOLET THUNDER GATE: electric cobalt, violet rock and flashes of icy lilac; unmistakable purple-blue storm arena",
          "storm", "thunder_violet", "#c3a7ff", "#9fbaff", "cracked dark violet mountain slabs with thin luminous cobalt thunder veins",
          "jagged mountain gate silhouette, monumental violet ceremonial drums, zigzag thunder rods, storm-cloud rim; no warm red shrine",
          ["storm pass: jagged violet basalt floor and diagonal cobalt thunder veins, exposed cloud edges",
           "drum summit: circular blue-violet drum-skin floor surrounded by rock teeth and large storm drums"]),
    theme("灰窑遗坊", "COPPER KILN WORKS: charcoal black, fired-clay terracotta and blazing copper-orange; industrial furnace identity",
          "ash", "kiln_copper", "#f59a4f", "#d29a79", "charcoal brick floor with muted copper heat seams and broad clay tiles",
          "round clay kilns, black chimney silhouettes, rusted kiln rails and orange furnace mouths; no temple altars",
          ["firing yard: long burnt-clay brick lanes with charcoal kiln mouths at the perimeter",
           "pottery workshop: dark clay hexagonal slabs and low copper rails, glazed terracotta urn shelves"]),
    theme("莲灯水阁", "AQUAMARINE LOTUS PAVILION: luminous turquoise, mint-green jade and pearl-white lotus; a light watery theme",
          "lotus", "lotus_aqua", "#a2f2dd", "#b5ecd9", "pale turquoise jade deck with shallow translucent aquamarine water channels",
          "curved mint-painted pavilion rails, large pearl lotus lamps, lily ponds and gently arched jade bridges",
          ["lotus pool deck: mint jade petal floor and curved water channels, pearl lotus edge lamps",
           "water pavilion: aquamarine geometric deck with shallow surrounding pools and sweeping jade railings"]),
    theme("白绫桥院", "SILVER FUNERAL BRIDGE: icy powder blue, frost white and silver-gray; cold airy high-key palette",
          "snow_silk", "bridge_frost", "#d4eaff", "#d4e0f2", "pale blue alabaster bridge deck, soft silver joints and a faint frost-paper pattern",
          "long suspended white silk ribbons, pale blue bridge railings and cold mist void beyond; no vermilion temple walls",
          ["silk bridge: long pale blue-white alabaster deck, flowing white funeral cloth at the sides",
           "mourning terrace: silver-white diamond slabs, looped white silk canopy and blue-gray mist beneath"]),
    theme("钟楼余响", "SUNLIT BRASS BELL TOWER: mustard yellow, warm ochre timber and weathered golden brass; mechanical tower identity",
          "dust", "belltower_ochre", "#f3d58a", "#d7b674", "warm mustard oak boards and circular brass gear inlays",
          "huge round bells, interlocking paper-cut gear silhouettes, wooden clock beams and counterweight ropes",
          ["bell chamber: ochre oak radial planks and a broad brass circle, hanging bells at the rim",
           "counterweight loft: yellow-brown checker timber floor, curved gears and suspended wooden weights"]),
    theme("竹影契林", "DEEP BAMBOO FOREST: bottle green, sap green and sharp yellow-green dappled light; vertical bamboo silhouette",
          "bamboo", "bamboo_forest", "#a9d777", "#86c774", "dark green packed forest earth, fine bamboo-leaf litter and dappled lime sunlight",
          "dense upright bamboo stems, segmented bamboo gates, woven reed fences and roots; no stone hall",
          ["bamboo glade: dark emerald earthen clearing with narrow lime light slashes and dense reed edges",
           "pledge grove: olive-green leaf floor and bent bamboo archways, yellow-green canopy light patches"]),
    theme("镜池回廊", "MIDNIGHT MIRROR GALLERY: near-black navy, cold ice cyan and reflective indigo; smooth geometric mirror identity",
          "mirror", "mirror_navy", "#80dcff", "#87c3eb", "smooth navy obsidian mirror tiles with thin cyan seams and subtle reflections",
          "angular cyan mirror panels, dark reflecting pools and geometric crystalline archways; no ivory candle chapel",
          ["reflection hall: deep navy square mirror floor, cyan-lit triangular mirror walls",
           "obsidian pool gallery: indigo diamond mirror floor with crescent pools and upright broken mirror fins"]),
    theme("封印石牢", "AMETHYST SEAL PRISON: deep grape purple, near-black plum and glowing magenta runes; heavy angular confinement",
          "seal", "prison_amethyst", "#ed91ff", "#c485dd", "large angular dark amethyst slabs with faint glowing violet geometric seal seams",
          "massive purple runestone blocks, chains, narrow angular cell doors and suspended magenta seal cords; no ordinary gray walls",
          ["sealed cell block: large purple slabs and square carved seals, massive angular cell rim",
           "binding vault: plum polygonal floor and radiating magenta seal seams, chain-weight alcoves"]),
    theme("万签焚堂", "ASHEN PETITION PYRE: soot black, ash white and dry rusty ember-red; paper rubble and burned timber",
          "cinder", "pyre_ash", "#ffac8d", "#c9b6ac", "scorched black wooden boards covered in pale torn blank petition fragments",
          "charred timber ribs, curled burnt paper piles, slashed broken roof and ash chimneys; ruin rather than a neat temple courtyard",
          ["burned petition hall: black timber floor with white ash scatter, collapsed charred roof ribs",
           "ash archive: ash-gray torn paper floor with long rust-red scorched seams and blackened scroll racks"]),
    theme("绳塔悬阁", "SKYBLUE ROPE SKY LOFT: clear cerulean, cloud white and pale blond timber; bright open sky around every edge",
          "wind", "skyloft_blue", "#d9f3ff", "#c1e3f7", "pale weathered suspended wooden platform with rope-seam square sections",
          "floating rope-tied timber platforms over a blue cloud abyss, rope balustrades and high suspension spars; NO enclosing masonry or shrine ceiling",
          ["hanging sky deck: pale blond timber platform, vivid blue sky and torn white cloud edges",
           "rope loft: beige rope-weave floor panels, skyblue abyss and slanting suspension cable silhouettes"]),
    theme("无名陵园", "MOONLIT NAMELESS CEMETERY: desaturated moon-cyan, blue-green gray and silver fog; irregular quiet graveyard",
          "mist", "cemetery_moon", "#c2dedf", "#aacbcf", "blue-green moonlit gravel and moss with irregular blank slate grave markers at the rim",
          "low eroded headstones, crooked cypress silhouettes, broken moon gates and ground fog; open outdoor cemetery",
          ["moon grave court: cool cyan gravel clearing and staggered blank gravestones, mist behind cypress trees",
           "forgotten burial garden: gray-teal moss earth and broken circular moon gate, scattered low blank stone plaques"]),
    theme("守名判殿", "REGAL MAGISTRATE COURT: deep ruby lacquer, ceremonial red-brown wood and old bronze-gold; massive solemn palace",
          "judgment", "court_ruby", "#e6b47c", "#d7a667", "dark ruby lacquer geometric court tiles with restrained symmetrical bronze lines",
          "monumental symmetrical bronze scales, tall ruby palace columns, huge seal-shaped throne alcove; more imposing than the small lantern market",
          ["name-weighing court: dark ruby rectangular tiles and a giant bronze balance behind the north entrance",
           "verdict hall: ruby-black diamond court floor, bronze scale pillars and a broad monumental throne outline"]),
    theme("万愿天穹", "COSMIC LEDGER VOID: midnight violet, starlight gold and pale lavender; celestial space, never an ordinary temple",
          "star", "cosmos_violet", "#e8ccff", "#e8cf91", "floating dark-violet paper-ledger plane with tiny gold constellation seams and lavender page corners",
          "disconnected floating ivory page islands, bronze celestial arcs, red-thread constellations and deep starry void beyond all four edges; NO masonry walls",
          ["constellation page: violet star-map floor and scattered floating ivory page islands, golden orbital perimeter arcs",
           "ledger heart approach: midnight lavender folded paper plane, a bronze cosmic-heart silhouette and luminous thin constellation filaments"]),
]

# Reviewed on the actual 1536 x 1024 source boards. Generated panel rows are
# sometimes unequal; their lower theme must never bleed into the upper arena.
ROOM_BOARD_SEAMS = {1: 512, 2: 480, 3: 512, 4: 510, 5: 457,
                    6: 511, 7: 512, 8: 494, 9: 512, 10: 490}

def reviewed_room_rects(board_index):
    seam = ROOM_BOARD_SEAMS[board_index]
    # Keep a 16px guard because lower-row foliage and crystal tips can protrude
    # into the upper panel. Outer arena walls and all four entrances are retained.
    upper_end = seam - 16
    return [[0, 0, 766, upper_end], [770, 0, 1536, upper_end],
            [0, seam + 2, 766, 1024], [770, seam + 2, 1536, 1024]]
