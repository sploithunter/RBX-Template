# Heaven & Hell Pet Design Prompts (layers 2–4)

Status: design — Jason, 2026-06. Meshy text-to-3D generation prompts for every roster pet in
layers 2, 3, and 4 (60 pets). Companion to [PET_REALM_HEAVEN_HELL_ROSTER.md](PET_REALM_HEAVEN_HELL_ROSTER.md)
(roles/rarity/odds) and the [Design Document](PET_REALM_DESIGN_DOCUMENT.md) (palette + dragon rules).

Pipeline: generate in Meshy → group upload → mesh combine (see the pet mesh/texture pipeline).
Remember the gotcha: the combine's `texture_asset` needs the **IMAGE** id, not the Decal id.

## How to use these

Each pet below is a **subject clause**. Build the final prompt as:

> `STYLE` + `<pet subject clause>` + (optional `GOLDEN` suffix)

### STYLE — prepend to every prompt
> Stylized cute Roblox-style collectible game pet, single creature, full body, centered, facing
> forward in a neutral idle pose, chunky rounded friendly proportions, clean smooth forms suited
> to low-poly game use, soft even shading, no base or platform, plain neutral background.

(Dragons & apexes: add "large, majestic, heroic, extra detail" — and note dragons need a higher
viewport zoom on import, per the existing dragon entries in `configs/pets.lua`.)

### Variant suffix — covers the gold version of EVERY pet
Golden is a **recolor of the same sculpt** — never change the silhouette. So a pet's golden
prompt is literally its base prompt + the GOLDEN suffix. This is why there is no separate
per-pet gold list: append it to any base below.

> **GOLDEN VARIANT** — identical sculpt and silhouette; re-skin the entire surface as lustrous
> polished gold with a bright metallic sheen and warm highlights; eyes become faceted gemstones;
> subtle golden sparkle. Recolor only, form unchanged.

> **Rainbow is NOT generated** — it's a runtime **effect** (shader / VFX overlay) on the base
> model, so it needs no prompt and no separate mesh. Only base + golden get generation prompts.

> Note: gold and rainbow are still the cross-cutting shiny tiers, so the **base** palettes below
> deliberately avoid gold/rainbow as a dominant color — that keeps a shiny reading as a shiny.

---

## Layer 2

### Heaven 2 — The Aurora Reaches  ·  palette: white / silver / pearl / prismatic / aurora; translucent, haloed, luminous

**Fire**
- **Coronal Cherub** — chubby winged cherub-imp wreathed in cool white flame, tiny halo, soft cyan glow.
- **Prism Lion** — stocky lion cub with a mane of refracting prismatic crystal shards, pearl-white fur.
- **Lance Seraph** — sleek four-winged seraph bird clutching a spear of white sunfire, silver plumage.
- **Lumen Salamander** — plump salamander of translucent glowing white light, soft aurora sheen along its back.
- **Dawnfire Phoenix** *(mythic apex)* — majestic phoenix of radiant white and pale-cyan feathers trailing soft light, luminous corona.

**Ice** *(dragon origin)*
- **Frostlight Doe** — dainty fawn of pale crystalline frost, faintly glowing antler-buds, prismatic hooves.
- **Prism Fox** — small fox with translucent prismatic-ice fur that refracts rainbow light, aurora-tipped tail.
- **Starlight Owl** — round owl of deep night-blue plumage speckled with starlight, glowing aurora eyes.
- **Glacial Archon** — armored angelic guardian of prismatic frost-glass with radiant shield-wings.
- **★ Aurora Dragon** *(secret)* — majestic prism-scaled dragon, translucent aurora-glowing scales, crystalline horns, frost breath; sturdy ground/melee build, not a slender flyer.

**Grass**
- **Bloomspirit Lamb** — fluffy lamb of soft white light with glowing flower-bud wool, tiny leaf halo.
- **Lightleaf Hare** — swift hare with translucent petal-like ears and faint light-wings, pearl fur.
- **Crystalbark Stag** — noble stag with glowing crystal-and-bark antlers, white pelt.
- **Radiant Sprite** — tiny floating bloom-spirit of glowing pollen motes with petal wings, pearl-green light.
- **Worldbloom Ent** *(mythic apex)* — towering gentle tree-guardian of living white light, blossoming canopy, glowing roots.

**Desert**
- **Glassling Scarab** — rounded beetle with a sun-fused translucent glass shell, faint prismatic glint.
- **Mirage Lynx** — lithe desert cat shimmering with heat-mirage translucency, pale sandy-white coat with light wisps.
- **Radiant Glass Sphinx** — regal seated sphinx carved of clear glass, refracting light, serene glowing eyes.
- **Sunwell Camel** — friendly camel with a glowing oasis-blue water-light hump, pale radiant coat.
- **Empyreal Roc** *(mythic apex)* — vast majestic bird of prey with radiant white-light feathers, prism-glinting talons.

### Hell 2 — The Frozen Dark  ·  palette: black / obsidian / black-ice / sickly-violet; frostbitten, hollow, cracked

**Fire**
- **Frostcinder Imp** — gaunt charred imp of black ice and cold blue-violet flame, hollow glowing eyes.
- **Rimemane Lion** — black frost-charred lion with a mane of jagged black ice, frostbitten hide.
- **Hoarfrost Phoenix** — dark skeletal phoenix wreathed in pale cold-blue fire, frost-rimed black feathers.
- **Frostbrand Salamander** — black salamander with glowing violet frostbite brands, icy cracked skin.
- **Deadfire Phoenix** *(mythic apex)* — ashen-black phoenix with a dying ember-violet glow, frost-tipped charred plumage.

**Ice** *(dragon origin)*
- **Rimegloom Hare** — gaunt frostbitten hare with black-ice fur, hollow pale eyes.
- **Dread Fox** — spectral black fox wreathed in chilling violet mist, eerie glowing stare.
- **Gravefrost Owl** — tattered black owl of frozen shadow, jagged ice feathers, violet eyes.
- **Black Archon** — fallen frost-angel in cracked black-ice armor with broken dark wings.
- **★ Rimewraith Dragon** *(secret)* — menacing black-ice revenant dragon, jagged frostbitten obsidian scales, violet inner glow, hollow eyes; sturdy ground/melee build.

**Grass**
- **Frostblight Lamb** — frozen rotted lamb, matted black-ice wool, sickly violet glow, hollow eyes.
- **Gloom Hare** — gaunt fanged frostbitten hare, dark patchy fur, pale dead eyes.
- **Icerot Stag** — decaying stag with black frozen thorns and ice-cracked antlers, rot-violet veins.
- **Rimewither Sprite** — withered dark frost-spirit shedding black pollen, violet glow.
- **Frostgrave Ent** *(mythic apex)* — massive frozen dead-tree guardian, black-ice bark, hollow knot-eyes, violet heart-glow.

**Desert**
- **Frostcarrion Scarab** — black beetle with a frost-cracked carapace, violet glint, feeding posture.
- **Wraithfrost Jackal** — spectral black-ice jackal shimmering like a cold mirage, hollow eyes.
- **Obsidian Sphinx** — seated guardian carved of black obsidian glass with sharp cracked edges, violet eyes.
- **Frostdust Camel** — gaunt frost-wraith camel, black-ice hump, breath of freezing dust.
- **Rime Roc** *(mythic apex)* — vast black-frost bird of prey, jagged ice feathers, frost-talons, violet eyes.

---

## Layer 3

### Heaven 3 — The Empyrean Bloom  ·  palette: white / pearl / living emerald-light; radiant flora, petals, glow

**Fire**
- **Gloryspark Cherub** — radiant cherub-mote of white flame with tiny emerald-light wings, soft halo.
- **Seraph Lion** — regal lion with a glowing white halo-mane edged in emerald light, pearl coat.
- **Radiant Lance** — graceful light-bird wielding a white sunfire lance, emerald-tipped wings.
- **Gloryscale Salamander** — salamander of glowing white light with emerald scale-sheen and a radiant aura.
- **Empyrean Phoenix** *(mythic apex)* — glorious phoenix of pure white radiance with emerald-light flame, near-blinding plumage.

**Ice**
- **Lumen Doe** — deer of soft white light with glowing emerald antler-buds, luminous coat.
- **Halo Fox** — white fox haloed in ringing light, emerald-glow tail, serene eyes.
- **Celestial Owl** — pearl owl speckled with starlight, emerald-glow eyes, soft light-feathers.
- **Radiant Archon** — angelic guardian of white-and-emerald prismatic light with radiant shield-wings.
- **Empyrean Leviathan** *(mythic apex)* — vast serene serpent of white light with emerald-glow fins, luminous scales.

**Grass** *(dragon origin)*
- **Gloryleaf Lamb** — lamb of green-white light with glowing leaf-wool, tiny bloom halo.
- **Halo Hart** — radiant young stag with a halo and glowing emerald antlers, pearl pelt.
- **Lightroot Stag** — sturdy stag with glowing root-and-light antlers, mossy radiant pelt.
- **Bloomlight Sprite** — floating harvest-spirit of glowing pollen and petals, emerald-white light.
- **★ Verdant Dragon** *(secret)* — colossal benevolent tree-dragon of living light, bark-and-leaf scales, a blossoming canopy crest, glowing emerald veins; massive heavy tank build.

**Desert**
- **Lightglass Scarab** — beetle with a glowing radiant-glass shell, emerald-light glint.
- **Radiant Lynx** — pale cat blurred with radiant light and glowing wisps, swift form.
- **Alabaster Sphinx** — seated guardian of smooth white alabaster stone with glowing eyes.
- **Glowwell Camel** — camel with a glowing light-spring hump, radiant pale coat.
- **Empyrean Roc** *(mythic apex)* — great radiant bird of white light, emerald-glint talons, luminous feathers.

### Hell 3 — The Blightmire  ·  palette: rot-green / black / bruise-violet; decay, bile, bone, drips

**Fire**
- **Blightcinder Imp** — sickly imp of green-rot fire, oozing cinders, hollow eyes.
- **Plaguemane Lion** — boil-maned lion with rotting green-black hide and a pustule glow.
- **Pyreblight Phoenix** — diseased phoenix wreathed in green pyre-flame, rotting feathers.
- **Rotbrand Salamander** — black salamander oozing green rot, glowing plague brands.
- **Pestilence Phoenix** *(mythic apex)* — gaunt plague-phoenix rising from green rot-ash, bile-dripping wings.

**Ice**
- **Murkfrost Hare** — bog-frosted hare, matted green-black fur, pale sick eyes.
- **Plague Fox** — spectral fox trailing green miasma, glowing diseased stare.
- **Carrion Owl** — ragged owl of rot and bone, green-glow eyes, tattered wings.
- **Rot Archon** — corroded fallen guardian in rotting armor, dripping bile.
- **Blight Leviathan** *(mythic apex)* — drowned bog-serpent of rot and slime, green-glow eyes, decaying fins.

**Grass** *(dragon origin)*
- **Blightleaf Lamb** — rotted lamb with green-black decayed wool, life-leech glow, hollow eyes.
- **Murk Hart** — gaunt bog-stag dripping moss, dead pale eyes.
- **Rotroot Stag** — decaying stag with rotting thorned antlers and oozing green veins.
- **Plaguebloom Sprite** — withered spirit shedding diseased green spores, bruise-violet glow.
- **★ Blight Dragon** *(secret)* — colossal rotting bog-dragon, decayed bark-and-bone scales, dripping bile, green-glow veins; massive heavy tank build, faint swarm of flies.

**Desert**
- **Carrionglass Scarab** — beetle with a rot-streaked glass shell, green glint, feeding posture.
- **Murk Jackal** — bog-mirage jackal, mottled green-black coat, hollow eyes.
- **Bonewaste Sphinx** — guardian of cracked bone and dark glass, green-glow eyes.
- **Plaguedust Camel** — gaunt camel exhaling sickly green dust, rotting hump.
- **Pestilent Roc** *(mythic apex)* — rot-feathered great bird, dripping talons, green-glow eyes.

---

## Layer 4

### Heaven 4 — The Sunspire Reaches  ·  palette: white / alabaster / sun-white / quartz; near-blinding, faceted glass (NO gold)

**Fire**
- **Sunspark Cherub** — radiant cherub-mote of brilliant white sun-fire, faceted light halo.
- **Blaze Lion** — powerful lion blazing with white-sun light, alabaster mane, glowing eyes.
- **Sunlance Seraph** — sleek light-bird hurling brilliant white sun-lances, quartz-tipped wings.
- **Sunscale Salamander** — salamander with faceted quartz scales glowing sun-white, radiant aura.
- **Solaris Phoenix** *(mythic apex)* — blinding white-sun phoenix with faceted light feathers and a radiant corona.

**Ice**
- **Sunfrost Doe** — deer of sun-glazed frost-quartz, glowing white antlers, faceted hooves.
- **Glare Fox** — white fox radiating blinding glare, quartz-sheen fur, bright eyes.
- **Sunbeam Owl** — pale owl of sun-white light, beam-glow eyes, faceted feathers.
- **Quartz Archon** — angelic guardian of clear faceted quartz with radiant sun-shield wings.
- **Sunspire Leviathan** *(mythic apex)* — vast serpent of sun-fused glass, faceted scales, radiant white glow.

**Grass**
- **Sunbloom Lamb** — lamb with glowing white sun-flower wool, faceted-light halo.
- **Sunleaf Hare** — bright hare with translucent quartz-leaf ears, sun-white coat.
- **Quartzbark Stag** — stag with faceted crystal-bark antlers glowing white, pale pelt.
- **Sunmote Sprite** — floating spirit of glowing sun-pollen with faceted light wings.
- **Sunroot Ent** *(mythic apex)* — towering sun-tree guardian of white light and quartz bark, radiant canopy.

**Desert** *(dragon origin)*
- **Sandglass Scarab** — beetle with a sun-fused translucent glass shell, brilliant glint.
- **Sunmirage Lynx** — cat shimmering with blinding heat-mirage, pale alabaster coat, light wisps.
- **Sunstone Sphinx** — seated guardian of smooth white sunstone with faceted edges, glowing eyes.
- **Sunspring Camel** — camel with a glowing oasis-light hump, radiant pale coat.
- **★ Alabaster Dragon** *(secret)* — colossal radiant desert dragon of smooth white alabaster and sun-fused glass, faceted translucent scales, crystalline horns, brilliant glow; sturdy agile bruiser build (NO gold).

### Hell 4 — The Scorchglass  ·  palette: black-glass / obsidian / ember-on-black; fractured glass, molten cracks, ash

**Fire**
- **Scorchcinder Imp** — obsidian imp veined with glowing ember cracks, smoldering shards.
- **Cindermane Lion** — black lion with molten-cracked obsidian hide and an ember-glow mane.
- **Magmaglass Phoenix** — dark phoenix of molten black glass with glowing ember-cracked feathers.
- **Scorchbrand Salamander** — obsidian salamander with glowing ember brands, cracked molten skin.
- **Inferno Phoenix** *(mythic apex)* — black-fire phoenix wreathed in ember-glow, fractured glass plumage.

**Ice**
- **Blackfrost Hare** — obsidian-frost hare, black-ice fur flecked with embers, cold glow.
- **Shatter Fox** — fox of fractured black glass with shard-fur, ember-glow eyes.
- **Obsidian Owl** — owl of sharp black-glass feathers, ember-glow eyes.
- **Scorch Archon** — fallen guardian in cracked obsidian armor, ember-veined wings.
- **Scorchglass Leviathan** *(mythic apex)* — serpent of molten black glass with glowing ember-cracked scales.

**Grass**
- **Scorchleaf Lamb** — charred lamb with burnt-glass wool, ember-glow, leech aura.
- **Cinder Hare** — ember-singed hare, blackened fur, glowing cracks.
- **Glassroot Stag** — stag with obsidian-thorn antlers and ember-veined black bark.
- **Scorchbloom Sprite** — withered spirit shedding ember-sparks, black-glass petals.
- **Scorchroot Ent** *(mythic apex)* — burnt-glass tree-guardian, obsidian bark with molten-ember cracks, glowing core.

**Desert** *(dragon origin)*
- **Obsidianglass Scarab** — beetle with a polished black-glass shell, ember glint.
- **Shatter Jackal** — jackal of fractured glass mirage with a shard-coat, ember eyes.
- **Blackglass Sphinx** — guardian carved of sharp black obsidian glass, ember-glow eyes.
- **Scorchdust Camel** — gaunt camel exhaling scorching ash, ember-cracked hump.
- **★ Glass Dragon** *(secret)* — colossal fractured black-glass desert dragon, razor obsidian scales veined with glowing ember cracks, jagged crystalline horns; sturdy agile bruiser build.

---

## Layer 5

### Heaven 5 — The Radiance  ·  palette: pure white / blinding light / prismatic halo; near-formless radiance (NO gold)

**Fire**
- **Seraph Cherub** — cherub-mote of pure blinding white light, faint halo, near-formless radiance.
- **Sol Lion** — powerful lion of brilliant white light, radiant mane, glowing form.
- **Empyrean Lance** — light-bird wielding a lance of pure white radiance, halo-glow wings.
- **Glory Salamander** — salamander of glowing white light with a radiant aura and prismatic halo sheen.
- **Sol Phoenix** *(mythic apex)* — supreme phoenix of pure white sun-radiance, blinding corona, near-formless light feathers.

**Ice**
- **Astral Doe** — deer of pure white starlight, glowing halo antlers, luminous near-translucent form.
- **Sol Fox** — white fox of radiant light, halo glow, serene bright eyes.
- **Astral Owl** — owl of pure starlight, constellation-speckled glow, radiant eyes.
- **Seraph Archon** — radiant angelic guardian of pure white light, halo, shield-wings.
- **Astral Leviathan** *(mythic apex)* — vast serpent of pure white starlight with halo-glow fins, luminous.

**Grass**
- **Eden Lamb** — lamb of pure white light with a radiant bloom halo, glowing wool.
- **Sol Hart** — radiant stag of white light, halo, glowing antlers.
- **Edenbark Stag** — stag with radiant white-light bark antlers, luminous pelt.
- **Eden Sprite** — floating spirit of pure light-pollen, radiant petal halo.
- **Edenroot Ent** *(mythic apex)* — towering tree-guardian of pure white light, radiant blossoming crown, glowing.

**Desert**
- **Sol Scarab** — beetle of glowing radiant white light, halo glint.
- **Astral Lynx** — cat of pure light, radiant blur, glowing wisps.
- **Eden Sphinx** — seated guardian of pure white light, serene halo, glowing eyes.
- **Sol Camel** — camel with a radiant white-light hump, glowing form.
- **Sol Roc** *(mythic apex)* — vast majestic bird of pure white radiance, halo-glow wings, blinding talons.

**Apex dragon (shared secret)**
- **★ Seraph Dragon** *(secret · hybrid)* — grand six-winged seraphic dragon of near-pure blinding white light, halo crown, radiant near-formless body; large, heroic, majestic apex build.

### Hell 5 — The Void  ·  palette: pure black / void / violet-red edge; light-devouring silhouettes

**Fire**
- **Umbral Imp** — imp of pure void-black, faint violet-red edge glow, light-devouring silhouette.
- **Void Lion** — black lion of pure void with a violet-red rim light, hollow form.
- **Abyss Phoenix** — phoenix of void-black with a violet-red ember edge, light-swallowing wings.
- **Null Salamander** — void-black salamander with violet-red brand glow, event-horizon skin.
- **Oblivion Phoenix** *(mythic apex)* — supreme void-black phoenix with a violet-red corona edge, devours surrounding light.

**Ice**
- **Umbral Hare** — void-black hare, violet-red rim, hollow eyes.
- **Void Fox** — fox of pure void, violet-red edge, light-swallowing form.
- **Abyss Owl** — owl of void-black, violet-red eye-glow, light-devouring feathers.
- **Null Archon** — fallen guardian of void-black with violet-red cracked armor.
- **Abyss Leviathan** *(mythic apex)* — vast serpent of pure void, violet-red rim, light-devouring scales.

**Grass**
- **Umbral Lamb** — void-black lamb, violet-red glow, hollow eyes (life-leech).
- **Void Hart** — gaunt void-black stag, violet-red rim.
- **Nullbark Stag** — stag of void-black bark with violet-red thorn glow.
- **Void Sprite** — withered void-spirit shedding black motes, violet-red glow.
- **Oblivionroot Ent** *(mythic apex)* — towering void-black tree-guardian, violet-red heart-glow, light-devouring.

**Desert**
- **Void Scarab** — beetle of pure void-black, violet-red glint.
- **Umbral Jackal** — void-black jackal, violet-red rim mirage, hollow eyes.
- **Abyss Sphinx** — guardian of void-black, violet-red edge, light-swallowing.
- **Null Camel** — gaunt void camel, violet-red breath, event-horizon hump.
- **Oblivion Roc** *(mythic apex)* — vast void-black bird, violet-red rim wings, light-devouring talons.

**Apex dragon (shared secret)**
- **★ Void Dragon** *(secret · hybrid)* — colossal dragon of pure void-black, an event-horizon silhouette edged in violet-red that devours surrounding light; large, heroic, menacing apex build.

---

## Not covered here (yet)

- **Layer 1** (Heaven 1 / Hell 1): art largely exists / in progress in `configs/pets.lua`.
