using System;

using Cacti;

namespace Meteorite;

class EnderChestBlockEntity : BlockEntity {
	public this(Vec3i pos) : base(BlockEntityTypes.ENDER_CHEST, pos) {}
}