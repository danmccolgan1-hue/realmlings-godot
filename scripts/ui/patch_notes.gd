class_name PatchNotes
extends Control
## Patch Notes on the start screen: one collapsible section per version, newest first, each with its date.
## The Godot port's own notes first, then the web game's (PATCH_NOTES, data/web/v106.json) that this port follows.
## web: v106.js renderPatchNotes

const PORT_NOTES := [
	{"v": "Godot 0.19", "date": "November 23, 2026", "items": [
		["Quests and relics", "Every full map hides the relics of six quests: rebuild a lost library, honor a forgotten war, answer a Mage's request, reclaim legendary battlegear, recover a Spell Book or a Lost Armament. Surveys uncover dig sites; Wayfinders dig; Reliquaries keep what they find; the Quest Log (L) keeps the story. Fallen Stars fall from 30 minutes in."],
		["Dedicated server", "Run the game on a rented server (docs/SERVER.md): the first player to join hosts, chooses the island, starts, saves and decides about drop-outs; the server keeps going when players leave, saves every minute, offers an interrupted game again after a restart, and stops when the game ends."],
		["Multiplayer saves and passwords", "The host saves a multiplayer game from the in-game menu and loads it in the lobby, where each player picks a nation from the save. The host may set a password for joining, and remove a player from the lobby."],
		["Debug in multiplayer", "The host's Allows Debug in the lobby lets every player use Settings → Debug: revealing the map and +2000 resources go to every player. Every technology now lets you choose your Magic school first."],
		["Digging failsafe", "A Wayfinder that keeps digging gets better odds: at least 10% a cycle after 3 minutes, 20% after 4, 30% after 5, 50% after 6, and the relic is certain after 7 minutes."],
		["Rewards", "Research every cycle for good, three Tier V armors, Jagkara's Cutlass, the Freak Man's Axe, the Maul of Greed, the Shield of Sham, the Triune Staff, Wall of Flame and Time Warp. Primal beasts roam when their hides are wanted."],
		["Multiplayer quests", "Dungeons, the Captured Royal Lady, captured envoys, generals, nobles, merchants and apprentices, ransom wars, Jailbreak, trading relics and prisoners, and Raid Reliquary and Free Prisoners at 50% warscore."],
		["Mason and armor", "The Mason's card shows the buildings that need no research; Advanced Buildings (U) opens the rest. Every armor costs 10% less."],
		["Multiplayer lobby", "Everyone but the host has a Ready button, and the host can't start until every player is ready. The host's island and computer nations show for everyone, and changing them asks everyone to be ready again. The lobby no longer redraws itself every time a ping arrives, so it stops flickering when someone joins. Two players with the same name are told apart (the second becomes \"Player 2\"), since the game keeps each nation by its player's name."],
		["Joining a game under way", "You can join a multiplayer game that has already started and choose your nation: one whose player is away, or one a player had before it was handed to the computer. Coming back under your old name still takes your own nation straight back, even before the host has noticed you were gone (that used to leave the game frozen), and once everyone who dropped out is back the game carries on by itself."],
		["Staying connected", "A player is only counted as dropped after 15 seconds without a word (it was 5), and the connection itself waits up to a minute before giving up, so a busy computer or a wobbly connection no longer throws people out. Every join, refusal, drop-out and resync is written to a multiplayer log (mp_log.txt) on each computer, and the lobby's Connection trouble? link explains what to check."],
		["Diplomacy", "Request Share Contacts: a nation that likes you shows you every nation it knows (a player is asked, and chooses). Each nation's title shows its opinion of you beside its difficulty. Meeting a new nation plays a fanfare, and its flag in the pop-up is half the size."],
		["Roads", "Press Road, click the province where the road starts and then the one where it ends: both must be yours, joined by your own land. The Mason walks the way and paves every border along it, one after another. A start that isn't yours, an end that isn't yours, or no way through your land is refused with a sound (a wrong end keeps your start); Esc, right-click or Cancel stops it. A road now speeds up anyone walking within three times its width of it (it looks the same), and every kind is 25% faster again (Dirt roads +50%)."],
		["Windows", "Diplomacy, the Armory, Research and the Players box can be dragged by their titles and stay where you leave them. The Players box can be turned off in Settings. Research closes once every tree with something on offer is researching (in multiplayer too), shows the icon of what each tree is researching, and the research circles in the banner fill properly."],
		["Bug reports", "A bug button sits top right in the game. Write what happened and press Submit: a screenshot and your text go to GitHub (paste a GitHub token under Settings › Bug reports), or are saved on your computer without one. Cancel clears the box and folds it away."],
		["Buildings and sounds", "Ordering a building, an outpost or an upgrade gives a confirming knock. The progress bar hangs over the building going up (an outpost shows its staked-out site), not over the Mason. Clicking the upgrade flag goes from building to building, selecting each one. Outposts and forts have houses of their own now, not only the capital's buildings."],
		["Units", "Chain and plate (Wyvern-Scaled and Dragonbone, Mithril and Ornate) show on your soldiers, on the map, in battle and in the Armory. Bandits and monsters show their army's power. Zombies look like Zombies in battle (they were drawn as infantry; they are half a Footman each, which is why they hit softly). Dragons and other monsters heave and sway as they move, and dragons beat their wings into the air."],
		["Fixes and smaller things", "A saved game no longer comes back with ruins under every gate in your walls. The Lost Travelers ask whichever player reaches them first, not only the host. The main menu's Exit is now Quit. Every island is a full island (the Practice island choice is gone). Aithne no longer starts with Automating Wayfinders. Tooltips show gold, wood and food as their icons."]]},
	{"v": "Godot 0.18", "date": "November 22, 2026", "items": [
		["New Game in two pages", "New Game: Nation (name, race, leader, color, flag and emblem color, then Continue) and New Game: Map Settings (seed, start position, island, peninsulas, coves, trees and opponents, then Start Game; Back returns to your nation). The main menu has an Exit button."],
		["New terrain", "A tenth of each terrain is something special. Drylands: golden grass swaying over the sand, 1 gold, 1 food and 1 wood, never beside a forest or mountains. Meadows: full of flowers, 2 gold, 3 food and 3 wood (a quarter of them one more of something), and each Farm there gives 3 more food. Fae Forests: darker and thicker, 1 gold, 3 food and 5 wood (a quarter one more), and each Lumber Mill there harvests 3 more wood. Bogs: pale with wide pools and mangroves, 2 of each; everyone but Swamplings wades through at half speed, defenders fight 30% harder, and buildings cost double (Swamplings: half)."],
		["Multiplayer lobby", "Change your name, choose Your Nation (anyone) and the Map Settings (the host) on the same pages as New Game, set each computer nation's difficulty and race, and press plain Leave and Start Game buttons. Two nations can't share a color or a leader: ones already taken are grayed out, and the game won't start while two match. The lobby no longer jumps when someone joins."],
		["Multiplayer rules", "The chat is gone (talk through Diplomacy). Swamplings growl and the others flirt, each once every 10 minutes per nation. Players may be at war with as many nations as they like. Bosses no longer show a count."],
		["Woodlings and flags", "Woodling villages have their own stump cottages. Swamplings and Woodlings no longer fly the Crown, Shield, Crossed swords or Eagle. A nation of another race is liked less (-100), so a Realmling allied with Woodlings isn't everyone's friend."],
		["Smaller things", "The messages box is fully see-through and a fifth shorter. Command card tooltips show after one second. Clicking a news flag no longer repeats it in the messages. A new minimap toggle hides the provinces nobody has claimed, and the country-color toggle's icon stays inside its square."],
		["Faster", "The map's little pictures (grass, rocks, flowers, trees, stepping stones) now share one texture and are drawn in a handful of batches; the swaying trees move in a shader instead of being redrawn 20 times a second; settlements, houses, villagers and units off the screen are skipped. On a full island the draw calls fall from about 2,000 to about 700."]]},
	{"v": "Godot 0.17", "date": "November 22, 2026", "items": [
		["Messages box", "Every message now goes to a see-through box beside the minimap. It keeps the last 48, shows 8 at a time, and has a scroll bar."],
		["Camera and mouse", "The game opens on your capital. Move the mouse to the edge of the screen to scroll. Only the middle mouse drags the map now, so right-click drags never get in the way of orders. Tooltips wait until the mouse has rested for 5 seconds."],
		["Mages join armies", "Select a Mage, Warlock or Druid standing with one of your armies and press Join army; Detach takes him out again."],
		["Allies and Death Mountain", "Allies share their sight with you. Death Mountain shows as soon as you see a province beside it."],
		["Swamplings and Woodlings", "Random nation names fit your race, tooltips use your race's words (Swampwright, Ogres...), the Ogre Cave and Barracks describe what they really do, Ogre Caves appear in the army outliner, and Swift and Hardy Ogres have Ogre-head icons."],
		["Screens", "The New Game page fits the screen, event choices are stacked and centered, meeting a nation shows its flag and leader, research options fold away once you pick one, the research strip shows each tree's banner, and the Army Training Order is smaller and sits under the Paused sign. The minimap draws one border around each nation, filled with its second color."],
		["Faster", "The map now draws far less each frame (about a seventh of the draw calls on a full island), and its waves and trees stop moving while the game is paused."]]},
	{"v": "Godot 0.16", "date": "November 22, 2026", "items": [
		["Diplomacy between players", "Other players appear in Diplomacy. Players have no opinion of each other, so Flirt and Growl just let them know, and there is no Bribe. Offering access is up to you; asking for access, an alliance (any race may ally any other), a Trade Network, Organized Crime or a white peace is up to them, with 30 seconds to answer. Proclaiming an enemy is heard by every player who has met you."],
		["Messages, proclamations and barter", "Send a message to one player (50 gold, up to 80 letters), issue a proclamation to every player you have met (100 gold), or barter any gold, wood and food for any in return: the other player has 30 seconds to accept. They arrive as flags."]]},
	{"v": "Godot 0.15", "date": "November 22, 2026", "items": [
		["Multiplayer", "Play together over your network or the internet. On the Multiplayer page, host a game, let your friends join, choose the island's seed and how many computer nations join you, and start. Everyone plays their own nation, with the race, leader and flag from their New Game page. New Game stays a single-player game."],
		["In the game", "A Players panel shows who is playing, their nation and connection, and a chat (press Enter). Anyone can pause; only the host or whoever paused can go on, and the banner says who paused."],
		["Drop-outs", "If a player drops out, the game pauses and everyone is told. The host can wait (the player joins again with the same name and takes their nation back) or hand the nation to the computer. If the host leaves, everyone keeps the game, and the host can continue it from the Multiplayer page."],
		["Staying in step", "Every copy of the game checks every few seconds that it matches the host's, and a copy that drifts is quietly sent the host's game again."]]},
	{"v": "Godot 0.14", "date": "November 22, 2026", "items": [
		["Several players in one game", "Under the hood, a game can now hold several human nations, each with its own treasury, research, fog of war, armies and orders, side by side with computer nations. A player who leaves can be handed to the computer mid-game. Every order you give now goes through one door, the same one a multiplayer game will send across the network. Playing together over the network comes next."]]},
	{"v": "Godot 0.13", "date": "November 21, 2026", "items": [
		["Multiplayer lobby", "Host a game or join one by address, and games on your own network show up by themselves. Up to 8 players see each other's nation and flag, chat, and see their connection speed. The host's game tries to open its port on the router by itself. Playing together comes next: for now the lobby lets you and your friends test your connections."],
		["Under the hood", "The game can now run in fixed steps and take a fingerprint of its whole state, and a new test proves that copies of a game stay exactly in step: the groundwork for playing together."]]},
	{"v": "Godot 0.12", "date": "November 21, 2026", "items": [
		["Flags", "Every race has its own flags. All keep the Crown, Shield, Crossed swords and Eagle. Realmlings add the Fleur-de-lis, Clenched fist, Heart and Rose; Swamplings the Flame, Bleeding eye, Beetle, Claw, Tooth, Skull, Crossed axes and Upside-down pyramid; Woodlings the Triskelion, Trinity knot, Celtic spiral, Great tree, Celtic knot, Shamrock, Dara knot and Shield knot. The Dragon, Horse, Snake and Lion are gone. Computer nations fly their race's flags too."],
		["Emblem color (0.12.1)", "Choose the color of your flag's emblem, on top of your nation's color: eight hues from light to deep, from white to a dark gray (no black). Computer nations get their own. The Tooth is now a set of fanged jaws, the Triskelion curls more and fits the flag, and the Flame and Bleeding eye take the emblem color like the rest."]]},
	{"v": "Godot 0.11", "date": "November 21, 2026", "items": [
		["Leaders", "Every Swampling and Woodling leader's bonus now works: Phlyo's free Sacred Pyres, Aarg's burning traps, Nihaarg's stronger curses, Sariel's Mending, Eliwen's weakening, Naobrien's Grand Elemental, Paladomis's bleeding blows, and cheaper Forges for Finn, Glurg and Alathandrious."],
		["Warlock skulls", "A Swampling Warlock with a wand holds a skull in the other hand: more attack, and a faster Fireball. Choose it in the Armory."],
		["Organized Crime", "Swampling nations can agree on Organized Crime: every Thug Den of both holds one more Thug. Swamplings form no Trade Networks."],
		["Computer nations", "Computer Pyromancers count their Sacred Pyres, and the counter designs Swampling and Woodling nations train are their own Berserkers and Protectors."],
		["Villages", "Houses grow around your buildings and developed settlements, and townsfolk walk between them, running indoors when danger comes. Realmlings, Swamplings and Woodlings each have their own, and two houses in three wear their nation's color on the roof (0.11.1)."],
		["Casting and dual wielding", "Mages, Warlocks and Druids raise their staff in their school's lightning while casting, and Berserkers with Dual Wielding carry both weapons on the map and in the Armory."]]},
	{"v": "Godot 0.10", "date": "November 21, 2026", "items": [
		["Grand Elemental", "Woodling Druids with the School of the Elements can call up a Grand Elemental: a towering man of living water who joins the army for 2 minutes."],
		["Lost travelers", "Swamplings capture lost travelers for food. Woodlings show them the way home for 30 research: Government with a Scout, Military with soldiers, Magic with a Druid."],
		["Growl", "Swampling leaders can growl at other nations: a Swampling nation may like it or not, anyone else takes it as a threat. Nobody flirts with a Swampling."],
		["Fire and stone on the map", "Scouting Pyres and Sacred Pyres burn, your fire traps smoulder along the province border and burst when sprung, Path of Fire licks at an army's heels, Fiery Weapons flare with ×2, Rock Armor circles an army with its stone bar, Whispering Rocks stand on the mountains, and Town Portals and the Grand Elemental splash."],
		["Animation", "Every settlement now smokes and waves its flags; Swampling and Woodling buildings animate like the Realmlings'; Swampstriders scurry on all fours and Ogres gallop."],
		["Type", "The interface is set in Alegreya, with titles in Cinzel Decorative."],
		["Minimap", "The minimap stays dark until you explore: no outline of the island or its coasts."]]},
	{"v": "Godot 0.9", "date": "November 21, 2026", "items": [
		["Swamplings", "Play as the Swamplings: start in a swamp with three Axe Berserkers, fight 20% harder and move 20% faster there, and tax your swamp settlements. Swampwrights, Swampstriders and Warlocks; Ogre Caves (mountain borders), Thug Dens with Thugs who earn gold, Supply Caches and Hot Springs; no Granaries, Storehouses or roads. Mushroom Farming from the start, Spiked Walls, the Fireball."],
		["Swampling war and magic", "Axes, Staghide, Wyvern-Scaled and Dragonbone armor, dual wielding (the off hand hits for half), and Ogres in five breeds. Pyromancy: Fiery Weapons, Scouting Pyres, fire traps, Path of Fire and Sacred Pyres."],
		["Woodlings", "Play as the Woodlings: start in a forest, 20% tougher and 10% quicker there; Scouts slip through borders of trees. Architects, Druids, Groves, Bazaars with Community, Shrines and the Hall of Champions; no shields or roads. Protectors with thrusting swords and a two-handed grip, Champions, Spiritweave, Mithril and Ornate armor."],
		["Woodling magic", "The School of the Elements: Rock Armor, Whispering Rocks, Town Portal and the Forest Spirit."],
		["New Game", "Choose your race; the leaders follow it, with all eight Swampling and eight Woodling leaders and their starts and bonuses. Each opponent can be a Realmling, Swampling, Woodling or a random race, with their own names, designs and schools."],
		["Look", "Swampling mud huts and Woodling tree houses, their buildings, soldiers, workers, townsfolk, icons and leader portraits; the Armory shows your race's gear."]]},
	{"v": "Godot 0.8", "date": "November 21, 2026", "items": [
		["Orders", "Drag a box to select several units, Shift-click to add or remove one. Right-click sends them all, spread out around the spot; hold Shift to queue orders. Ctrl+right-click opens the survey and build menu (or turn on Quick queue in Settings). Drag with the right mouse to move the map."],
		["On the map", "A golden mark where you sent units, numbered markers for queued surveys and moves, the survey's loop and stakes, rally points, and the provinces of your selected units."],
		["Battles and spells", "Battles show the melee, each side's strength, the blows and the fallen. Forts with Arrowslits now shoot invaders. Casting circles, Shockwaves, Earthquakes, forest paths and tunnels are drawn."],
		["Animation", "Units pop in, breathe, hop as they walk and throw sparks as they build; buildings smoke, wave their flags and turn their wheels, and the Mage Tower's crystals circle."],
		["Sound", "Music and every sound effect of the web game, with their switches and volumes; M turns the music on or off."]]},
	{"v": "Godot 0.7", "date": "November 21, 2026", "items": [
		["Armory", "Laid out as the web game’s: your designs with portraits and stats, a spinning preview, stat bars, and the gear as picture buttons under Weapons, Armor and Horses tabs. Equip every Mage with staves, wands and shields, and retrofit your armies from the Armory."],
		["Magic", "Choose your school of magic when your first Mage Tower stands. Abandon Magic School now works: the school and its spells are forgotten and you choose again."],
		["Country Breakdown", "Click your flag and name, top left: your leader, land, where your resources come from and go, your artifacts and your wars."],
		["Diplomacy", "One section per nation you have met, with its leader’s portrait and likes, what you know of it, the agreements between you, the war and its peace terms, and the diplomatic actions as picture buttons. Hover a nation to see its opinion of you."]]},
	{"v": "Godot 0.6", "date": "November 21, 2026", "items": [
		["Start screen", "The web game’s title card: a parade of your folk, Continue, New Game, Tutorial, Multiplayer, Patch Notes, Load a save file, Recorded games, Settings and How to play, over a drifting island."],
		["New Game", "Choose your seed and nation name (with dice), leader from portrait cards, color, flag, start position, the island’s shape with peninsulas, coves and trees, and each of the seven opponent slots. Your choices are remembered."],
		["Saves", "Export a game to a file and load it again, from the menu and the in-game menu."],
		["Renaming", "Rename provinces and your units with the ✎ buttons."],
		["Main screen", "The icon command card, the outliner’s tabs, the province menu with its plots, resource badges and names on the map, the minimap’s toggles, crops on Farms, and the hidden landmarks: Death Mountain, the Oasis, the Heart of the Forest, set pieces, ruins, treasure and travelers."]]},
	{"v": "Godot 0.5", "date": "November 20, 2026", "items": [
		["Flags", "Notification flags hang above the command card: idle research, Army Exhaustion, open plots, upgrades, quakes, truces ending, warscore at 100, white peace coming, spells ready, requests waiting, war news and the province limit. Left-click deals with one, right-click dismisses it."],
		["Tooltips", "Every command, training and building button explains what it does, what it costs and why it can’t be used yet. The resource bar shows what comes in and what upkeep takes."],
		["Settings", "A Settings window: interface size, full screen, Calm map, Record games, and debug switches. Settings are remembered."],
		["Recordings", "Turn on Record games to keep a recording of each full-map game, then watch it back from the start screen: the map as it changed, with every nation’s growth."],
		["Windows", "A Windows build, with its own icon and version number. Saved games carry a version so newer builds still load them."]]},
	{"v": "Godot 0.4", "date": "November 20, 2026", "items": [
		["Diplomacy", "Flirt, gifts, alliances asked and offered, military access, Trade Networks, spies and bribes, each with the reason it isn’t possible yet. Requests from other nations wait in a box with a timer. Gift vaults and war news."]]},
	{"v": "Godot 0.3", "date": "November 20, 2026", "items": [
		["Sieges", "Armies batter walls down; forts and capitals rebuild them."],
		["Magic", "Shockwave and Earthquake, for you and the computer nations."],
		["Bosses", "Boss fights and the nine artifacts, Winged Slippers included. Intact Ruins give a technology."]]},
	{"v": "Godot 0.2", "date": "November 20, 2026", "items": [
		["Full maps", "Full-size worlds with up to six computer nations that build, research, train and go to war."],
		["Wars", "Wars, warscore, peace terms, truces, alliances, opinion and Proclaim Enemy, in a Diplomacy window (Y)."]]},
	{"v": "Godot 0.1", "date": "November 19–20, 2026", "items": [
		["The Practice island", "The web game’s map generator, economy, building, surveying, research, training, the Armory, magic, battles, roads, walls, development, saving and the Basic Tutorial."]]},
]

var win: Dictionary
var box: VBoxContainer
var open_v := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win = UiKit.window("Patch Notes", 760, func(): close())
	add_child(win.panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.body.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	open_v[PORT_NOTES[0].v] = true
	win.panel.hide()


func all_notes() -> Array:
	var out := PORT_NOTES.duplicate()
	for P in GameData.c("PATCH_NOTES"):
		out.append({"v": "Web game " + str(P.v), "date": P.date, "items": P.items})
	return out


func open() -> void:
	_fill()
	win.panel.show()
	UiKit.center.call_deferred(win.panel)


func close() -> void:
	win.panel.hide()


func _fill() -> void:
	UiKit.clear(box)
	for P in all_notes():
		var on: bool = open_v.has(P.v)
		var head := UiKit.button("%s %s   ·   %s" % ["▾" if on else "▸", P.v, P.date], 19)
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var v: String = P.v
		head.pressed.connect(func():
			if open_v.has(v):
				open_v.erase(v)
			else:
				open_v[v] = true
			_fill())
		box.add_child(head)
		if on:
			var r := UiKit.rich(17, 700)
			r.text = "\n".join(P.items.map(func(it): return "• [b]%s.[/b] %s" % [it[0], it[1]]))
			box.add_child(r)
