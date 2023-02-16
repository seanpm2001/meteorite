using System;

namespace Meteorite;

class BlockItem : Item {
	public Block block;

	[AllowAppend]
	public this(ResourceKey key, int32 id, Block block, ItemSettings settings) : base(key, id, settings) {
		this.block = block;
	}
}