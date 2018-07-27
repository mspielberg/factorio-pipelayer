1. player disconnects while in plumbing view
2. player takes damage while in plumbing view
3. player is killed while in plumbing view

# TODO

1. support multiple surfaces
2. ghost handling

# to test

1. placing surface when underground is obstructed

# blueprints

(DONE) creating a blueprint with a via also blueprints underground pipes within the region
(DONE) placing blueprint places ghosts underground
(DONE) invisible chest with item requests on 1st via aboveground
if via or via ghost is mined, give items to player / spill to player location / set deconstruct order on invisible chest
if via or via ghost is destroyed, destroy chest and its contents
on tick, use pipes in chest to revive underground ghosts
when all ghosts revived, destroy chest if empty, mark for deconstruction otherwise

if item request proxy is mined, put any contents to player, or destroy destroy chest if empty, mark for deconstruction otherwise