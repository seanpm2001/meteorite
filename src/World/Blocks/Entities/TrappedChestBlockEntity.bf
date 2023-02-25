using System;

using Cacti;

namespace Meteorite;

class TrappedChestBlockEntity : BlockEntity {
	public this(Vec3i pos) : base(BlockEntityTypes.TRAPPED_CHEST, pos) {}
}