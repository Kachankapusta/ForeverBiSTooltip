Forever BiS Tooltip

A standalone addon for WoW Forever, Interface 16001.
Open it with /bistooltip, /fbt, or the minimap button.

Choose a class and specialization to browse the regular and Realistic
Pre-Raid lists. The Realistic toggle applies to the gear window and item
tooltips. The Only selected spec option follows the specialization you
choose in the window. Your selection is saved per character.

The window uses a compact grid in the bronze style of WoW Forever. Each
equipment slot occupies one row, with the BiS pick on the first page.
Resizing the window changes how many icons fit on each page. Page controls
disappear when all items fit. Hover over an item to see its name and source.
Open Settings → AddOns → Forever BiS Tooltip in WoW or click the gear icon
in the BiS window. Drag the bottom-right corner to resize the window.

In tooltips, Top 1, Top 2, and so on show an item's position in the list.
If an item appears in two slots for the same specialization, the tooltip
shows its highest rank. Icons next to each slot show enchants and gem
recommendations when available. Enchant tooltips show effects and materials
for crafting or quest exchanges. Item tooltips show item stats and sockets.
The current Pre-Raid source has no gem recommendations. Equipped and In bags
refer to the current character. If Ctrl only is enabled, hold Ctrl before
hovering over an item.

Left-click an enchant or gem to add one set of materials to the shopping
list. Right-click removes one set, and Shift + left-click opens the recipe
or item for inspection. Open Shopping from the BiS window or from the side
tab at the auction house. The panel docks on the right of the auction house
and closes with the same tab or when you close the auction house.
The shopping list shows how many materials you own and how many you need,
and it is saved per character.

If Auctionator is installed, missing materials that can be purchased are
sent to the Forever BiS Shopping list. It updates as your inventory changes.
The Shopping panel also shows bound items and gold needed for quest exchanges.

Gear recommendations come from https://wowtbc.gg/warcraftforever/bis-list/
The footer shows the date of the bundled data snapshot. The addon uses
that snapshot in-game.

To update the database, run this command from the AddOns folder with Node.js
installed.

node ForeverBiSTooltip/tools/import-wowtbc.mjs

To test the importer, run the following command.

node --test ForeverBiSTooltip/tests/import-wowtbc.test.mjs

The importer downloads public data for every specialization and replaces
Data.lua after all pages have been processed successfully. Level-capped
lists are excluded. Run /reload in WoW after updating the database.

To add a phase, import its data and add its description to stages in
Core.lua. If the source structure is unsupported, the importer reports
the error and keeps the existing database.

Publishing

On main, GitHub Actions checks for data updates at 09:17 and 21:17 Warsaw
time. To run it manually, select Update WowTBC data in Actions.
The workflow runs tests and commits Data.lua when the recommendations change.

To enable automatic uploads, create a CurseForge project for WoW Forever
1.60.1 and submit the first ZIP for moderation. In GitHub Settings →
Secrets and variables → Actions, add the CurseForge author token as
the CF_API_TOKEN secret and the numeric project ID as the
CURSEFORGE_PROJECT_ID variable.

The next data change queues a release. After a successful upload, the
workflow records the CurseForge file ID in the tag
curseforge/<project ID>/<commit>. If the upload times out, check the
author dashboard before retrying.
