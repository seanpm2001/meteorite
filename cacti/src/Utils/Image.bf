using System;
using System.IO;
using System.Collections;

using MiniZ;
using stb_image;

namespace Cacti;

struct ImageInfo : this(Vec2i size, int components) {
	public int Width => size.x;
	public int Height => size.y;

	public static Result<Self> Read(StringView path) => Image.ReadInfo(path);
}

class Image {
	public Vec2i size;
	public int components;
	public uint8* pixels;

	private bool stbFree;

	public this(Vec2i size, int components, uint8* pixels, bool stbFree) {
		this.size = size;
		this.components = components;
		this.pixels = pixels;
		this.stbFree = stbFree;
	}

	public ~this() {
		if (stbFree) stbi.stbi_image_free(pixels);
	}

	public int Width => size.x;
	public int Height => size.y;
	public uint64 Bytes => (.) (size.x * size.y * components);

	public ref Color Get(int x, int y) {
		return ref ((Color*) pixels)[y * size.x + x];
	}

	// Writing

	public void Write(StringView path, bool isBgra = false, bool bgraNoAlpha = true) {
		if (components != 4) return;

		FileStream s = scope .();
		s.Create(path, .Write);

		// Header
		s.Write<uint8>(0x89);
		s.WriteStrUnsized("PNG");
		s.Write<uint8>(0x0D);
		s.Write<uint8>(0x0A);
		s.Write<uint8>(0x1A);
		s.Write<uint8>(0x0A);

		// Image Header
		{
			List<uint8> chunkData = new .();
			MemoryStream cs = scope .(chunkData);

			WriteBigEndian(cs, (.) size.x); // Width
			WriteBigEndian(cs, (.) size.y); // Height
			cs.Write<uint8>(8); // Bit depth
			cs.Write<uint8>(6); // Color type
			cs.Write<uint8>(0); // Compression method
			cs.Write<uint8>(0); // Filter method
			cs.Write<uint8>(0); // Interlace method
			
			WriteChunk(s, "IHDR", chunkData.Ptr, chunkData.Count);
		}

		// Image Data
		{
			List<uint8> chunkData = new .();
			MemoryStream cs = scope .(chunkData);

			int dataLength = size.x * size.y * components + size.y;
			uint8* data = new .[dataLength]*;
			for (int y < size.y) {
				uint8* row = &data[y * (size.x * components + 1)];

				row[0] = 0;

				if (isBgra) {
					for (int x < size.x) {
						uint8* pixel = &this.pixels[y * (size.x * components) + x * components];

						row[1 + x * components] = pixel[2];
						row[1 + x * components + 1] = pixel[1];
						row[1 + x * components + 2] = pixel[0];
						row[1 + x * components + 3] = bgraNoAlpha ? 255 : pixel[3];
					}
				}
				else Internal.MemCpy(&row[1], &this.pixels[y * (size.x * components)], size.x * components);
			}

			int compressedLength = dataLength;
			uint8* compressedData = new uint8[compressedLength]*;
			MiniZ.Compress(compressedData, ref compressedLength, data, dataLength);

			cs.TryWrite(.(compressedData, (.) compressedLength));

			delete compressedData;
			delete data;

			WriteChunk(s, "IDAT", chunkData.Ptr, chunkData.Count);
		}

		// Image End
		WriteChunk(s, "IEND", null, 0);
	}

	private static void WriteChunk(Stream s, StringView type, uint8* buffer, int length) {
		WriteBigEndian(s, (.) length);
		s.WriteStrUnsized(type);
		s.TryWrite(.(buffer, length));

		CRC crc = .();
		crc.Add((.) type.Ptr, type.Length);
		crc.Add(buffer, length);
		WriteBigEndian(s, crc.Get());
	}

	private static void WriteBigEndian(Stream s, uint32 value) {
		var value;
		uint8* data = (.) &value;
		uint8[4] buffer;

		buffer[0] = data[3];
		buffer[1] = data[2];
		buffer[2] = data[1];
		buffer[3] = data[0];

		s.TryWrite(.(&buffer, 4));
	}

	private struct CRC {
		private static uint32[256] TABLE = .(
			0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
			0x0eDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
			0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
			0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
			0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
			0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
			0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
			0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
			0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
			0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
			0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
			0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
			0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
			0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
			0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
			0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
			0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
			0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
			0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
			0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
			0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
			0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
			0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
			0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
			0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
			0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
			0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
			0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
			0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
			0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
			0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
			0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
		);

		private uint32 crc = ~0u;

		public void Add(uint8* buffer, int length) mut {
			for (int i < length) {
				crc = (crc >> 8) ^ TABLE[buffer[i] ^ (crc & 0xff)];
			}
		}

		public uint32 Get() => ~crc;
	}
	// Loading

	public static Result<Image> Read(StringView path, int components = 4, bool flip = false) {
		int32 width = 0;
		int32 height = 0;
		int32 comp = 0;

		FileStream fs = scope .();
		if (fs.Open(path, .Read, .Read) case .Err) return .Err;

		stbi.stbi_set_flip_vertically_on_load(flip);
		uint8* pixels = stbi.stbi_load_from_callbacks(&IO_CALLBACKS, Internal.UnsafeCastToPtr(fs), &width, &height, &comp, (.) components);
		if (pixels == null) return .Err;

		// Either the STB Image port does not correctly return the required components argument as the components in the image or the original STB also does not do this, don't know
		return new Image(.(width, height), components, pixels, true);
	}

	public static Result<ImageInfo> ReadInfo(StringView path) {
		int32 width = 0;
		int32 height = 0;
		int32 comp = 0;

		FileStream fs = scope .();
		if (fs.Open(path, .Read, .Read) case .Err) return .Err;

		bool ok = stbi.stbi_info_from_callbacks(&IO_CALLBACKS, Internal.UnsafeCastToPtr(fs), &width, &height, &comp);
		if (!ok) return .Err;
		
		return ImageInfo(.(width, height), comp);
	}

	private static stbi.stbi_io_callbacks IO_CALLBACKS = .() {
		read = => IoRead,
		skip = => IoSkip,
		eof = => IoEof
	};

	private function void stbi_write_func(void *context, void *data, int32 size);
	private static stbi_write_func IO_WRITE = => IoWrite;

	private static int32 IoRead(void* user, uint8* data, int32 size) {
		FileStream fs = (.) Internal.UnsafeCastToObject(user);
		return (.) fs.TryRead(.(data, size));
	}

	private static void IoSkip(void* user, int32 n) {
		FileStream fs = (.) Internal.UnsafeCastToObject(user);
		fs.Skip(n);
	}

	private static bool IoEof(void* user) {
		FileStream fs = (.) Internal.UnsafeCastToObject(user);
		return fs.Position >= fs.Length - 1;
	}

	private static void IoWrite(void* context, void* data, int32 size) {
		FileStream fs = (.) Internal.UnsafeCastToObject(context);
		fs.TryWrite(.((.) data, size));
	}
}