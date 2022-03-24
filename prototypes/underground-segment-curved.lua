local Utils = require("utility.utils")

-- Collision box is off center so that its built on the rail grid and not 1 tile off in 1 direction based upon rotation.

local undergroundSegmentCurvedRegular = {
    type = "simple-entity-with-owner",
    name = "railway_tunnel-underground_segment-curved-regular",
    icon = "__railway_tunnel__/graphics/icon/underground_segment-curved/railway_tunnel-underground_segment-curved.png",
    icon_size = 32,
    localised_name = {"item-name.railway_tunnel-underground_segment-curved"},
    localised_description = {"item-description.railway_tunnel-underground_segment-curved"},
    collision_box = {{-4.9, -2.9}, {2.9, 2.9}},
    collision_mask = {"item-layer", "object-layer", "water-tile"},
    selection_box = {{-4.9, -2.9}, {2.9, 2.9}},
    max_health = 1000,
    resistances = data.raw["wall"]["stone-wall"].resistances,
    flags = {"player-creation", "not-on-map"},
    picture = {
        north = {
            filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-regular-north.png",
            height = 192,
            width = 256,
            shift = {-1, 0}
        },
        east = {
            filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-regular-east.png",
            height = 256,
            width = 192,
            shift = {0, -1}
        },
        south = {
            filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-regular-south.png",
            height = 192,
            width = 256,
            shift = {1, 0}
        },
        west = {
            filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-regular-west.png",
            height = 256,
            width = 192,
            shift = {0, 1}
        }
    },
    render_layer = "ground-tile",
    minable = {
        mining_time = 1,
        result = "railway_tunnel-underground_segment-curved-regular",
        count = 1
    },
    placeable_by = {
        item = "railway_tunnel-underground_segment-curved-regular",
        count = 1
    },
    corpse = "railway_tunnel-underground_segment-curved-regular-remnant"
}

local undergroundSegmentCurvedRegularItem = {
    type = "item",
    name = "railway_tunnel-underground_segment-curved-regular",
    icon = undergroundSegmentCurvedRegular.icon,
    icon_size = undergroundSegmentCurvedRegular.icon_size,
    subgroup = "train-transport",
    order = "a[train-system]-a[rail]e",
    stack_size = 50,
    place_result = "railway_tunnel-underground_segment-curved-regular"
}

local undergroundSegmentCurvedRegularTopLayer = {
    type = "simple-entity-with-owner",
    name = "railway_tunnel-underground_segment-curved-regular-top_layer",
    icon = undergroundSegmentCurvedRegular.icon,
    icon_size = undergroundSegmentCurvedRegular.icon_size,
    subgroup = "railway_tunnel-other",
    collision_box = nil,
    collision_mask = {},
    selection_box = nil,
    flags = {"not-on-map", "not-repairable", "not-blueprintable", "not-deconstructable", "no-copy-paste", "not-upgradable"},
    picture = {
        north = {
            filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-top_layer-northsouth.png",
            height = 192,
            width = 256,
            shift = {-1, 0}
        },
        east = {
            filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-top_layer-eastwest.png",
            height = 256,
            width = 192,
            shift = {0, -1}
        },
        south = {
            filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-top_layer-northsouth.png",
            height = 192,
            width = 256,
            shift = {1, 0}
        },
        west = {
            filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-top_layer-eastwest.png",
            height = 256,
            width = 192,
            shift = {0, 1}
        }
    },
    render_layer = "tile-transition"
}

--TODO: needs some sort of rotation shifting as our real entity isn'd equal sized when rotated.
local undergroundSegmentCurvedRegularRemnant = {
    type = "corpse",
    name = "railway_tunnel-underground_segment-curved-regular-remnant",
    icon = undergroundSegmentCurvedRegular.icon,
    icon_size = undergroundSegmentCurvedRegular.icon_size,
    icon_mipmaps = undergroundSegmentCurvedRegular.icon_mipmaps,
    flags = {"placeable-neutral", "not-on-map"},
    subgroup = "remnants",
    order = "d[remnants]-b[rail]-z[portal]",
    selection_box = undergroundSegmentCurvedRegular.selection_box,
    selectable_in_game = false,
    time_before_removed = 60 * 60 * 15, -- 15 minutes
    final_render_layer = "remnants",
    remove_on_tile_placement = false,
    animation = {
        filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-remnant.png",
        line_length = 1,
        width = 256,
        height = 256,
        frame_count = 1,
        direction_count = 4
    }
}

-- Second set of 4 rotations entity.

-- The minining of the flipped curve intentionally gives the regular curve item as we want the player to only ever have the regular item in their inventory.
local undergroundSegmentCurvedFlipped = Utils.DeepCopy(undergroundSegmentCurvedRegular)
undergroundSegmentCurvedFlipped.name = "railway_tunnel-underground_segment-curved-flipped"
undergroundSegmentCurvedFlipped.placeable_by = {
    -- The order seems irrelevent in which is returned by Q (smart-pipette) as the item's place_result seems to take priority and thus gives regular curve. Can react to the smart-pipette action and give the correct item via script.
    {
        item = "railway_tunnel-underground_segment-curved-flipped",
        count = 1
    },
    {
        item = "railway_tunnel-underground_segment-curved-regular",
        count = 1
    }
}
undergroundSegmentCurvedFlipped.picture = {
    north = {
        filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-flipped-north.png",
        height = 192,
        width = 256,
        shift = {1, 0}
    },
    east = {
        filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-flipped-east.png",
        height = 256,
        width = 192,
        shift = {0, 1}
    },
    south = {
        filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-flipped-south.png",
        height = 192,
        width = 256,
        shift = {-1, 0}
    },
    west = {
        filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-flipped-west.png",
        height = 256,
        width = 192,
        shift = {0, -1}
    }
}
undergroundSegmentCurvedFlipped.collision_box = {{-2.9, -2.9}, {4.9, 2.9}}
undergroundSegmentCurvedFlipped.selection_box = {{-2.9, -2.9}, {4.9, 2.9}}
undergroundSegmentCurvedFlipped.corpse = "railway_tunnel-underground_segment-curved-flipped-remnant"

local undergroundSegmentCurvedFlippedItem = Utils.DeepCopy(undergroundSegmentCurvedRegularItem)
undergroundSegmentCurvedFlippedItem.name = "railway_tunnel-underground_segment-curved-flipped"
undergroundSegmentCurvedFlippedItem.place_result = "railway_tunnel-underground_segment-curved-flipped"
undergroundSegmentCurvedFlippedItem.order = "a[train-system]-a[rail]f"
undergroundSegmentCurvedFlippedItem.localised_name = {"item-name.railway_tunnel-underground_segment-curved-flipped"}
undergroundSegmentCurvedFlippedItem.localised_description = {"item-description.railway_tunnel-underground_segment-curved-flipped"}

local undergroundSegmentCurvedFlippedTopLayer = Utils.DeepCopy(undergroundSegmentCurvedRegularTopLayer)
undergroundSegmentCurvedFlippedTopLayer.name = "railway_tunnel-underground_segment-curved-flipped-top_layer"
undergroundSegmentCurvedFlippedTopLayer.picture = {
    north = {
        filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-top_layer-northsouth.png",
        height = 192,
        width = 256,
        shift = {1, 0}
    },
    east = {
        filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-top_layer-eastwest.png",
        height = 256,
        width = 192,
        shift = {0, 1}
    },
    south = {
        filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-top_layer-northsouth.png",
        height = 192,
        width = 256,
        shift = {-1, 0}
    },
    west = {
        filename = "__railway_tunnel__/graphics/entity/underground_segment-curved/underground_segment-curved-top_layer-eastwest.png",
        height = 256,
        width = 192,
        shift = {0, -1}
    }
}

--TODO: probably needs own copy of animation and rotation based shifting?
local undergroundSegmentCurvedFlippedRemnant = Utils.DeepCopy(undergroundSegmentCurvedRegularRemnant)
undergroundSegmentCurvedFlippedRemnant.name = "railway_tunnel-underground_segment-curved-flipped-remnant"

data:extend(
    {
        undergroundSegmentCurvedRegular,
        undergroundSegmentCurvedRegularItem,
        undergroundSegmentCurvedRegularTopLayer,
        undergroundSegmentCurvedRegularRemnant,
        undergroundSegmentCurvedFlipped,
        undergroundSegmentCurvedFlippedItem,
        undergroundSegmentCurvedFlippedTopLayer,
        undergroundSegmentCurvedFlippedRemnant
    }
)