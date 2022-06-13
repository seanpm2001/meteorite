using System;

namespace Meteorite {
	class LoginDisconnectS2CPacket : S2CPacket {
		public const int32 ID = 0x00;

		public Text reason ~ delete _;

		public this() : base(ID) {}

		public override void Read(NetBuffer buf) {
			reason = buf.ReadText();
		}
	}
}