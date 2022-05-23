using System;
using System.Collections;
using System.Diagnostics;

namespace Meteorite{
	static class BlockModelLoader {
		private static float MIN_SCALE = 1f / Math.Cos(0.3926991f) - 1f;
		private static float MAX_SCALE = 1f / Math.Cos(0.7853981852531433f) - 1f;

		private static Dictionary<String, Json> MODEL_CACHE;

		public static void LoadModels() {
			Stopwatch sw = scope .(true);
			//let omg = Profiler.StartSampling();

			MODEL_CACHE = new .();
			Dictionary<String, List<(Quad, uint16[4])>> textures = new .();

			// Load models
			for (Block block in Registry.BLOCKS) {
				// Read blockstate json
				Json? blockstateJson = GetMergedBlockstateJson(block);

				if (blockstateJson == null) {
					Log.Error("Failed to find blockstate file for block with id '{}'", block.id);
				}

				// Loop all block states
				for (BlockState blockState in block) {
					Model model = new .();

					if (blockstateJson != null) {
						if (blockstateJson.Value.Contains("multipart")) {
							List<RawModel> modelJsons = GetMultipartModels(blockState, blockstateJson.Value);
	
							for (RawModel rawModel in modelJsons) {
								for (let j in rawModel.json["elements"].AsArray) {
									ParseElement(block, textures, model, rawModel.json, j, rawModel.rotation);
								}
							}
	
							DeleteContainerAndDisposeItems!(modelJsons);
						}
						else {
							if (GetVariantModel(block, blockState, blockstateJson.Value) case .Ok(let rawModel)) {
								if (rawModel.json.Contains("elements")) {
									for (let j in rawModel.json["elements"].AsArray) {
										ParseElement(block, textures, model, rawModel.json, j, rawModel.rotation);
									}
								}
	
								rawModel.Dispose();
							}
						}
					}

					model.Finish();
					blockState.model = model;
				}

				blockstateJson.Value.Dispose();
			}

			// Create texture atlas
			TextureManager t = Meteorite.INSTANCE.textures;

			for (let pair in textures) {
				let texture = t.Add(scope $"{pair.key}.png");

				for (let a in pair.value) {
					a.0.region = .(
						(.) (a.1[0] / 16f * uint16.MaxValue),
						(.) (a.1[1] / 16f * uint16.MaxValue),
						(.) (a.1[2] / 16f * uint16.MaxValue),
						(.) (a.1[3] / 16f * uint16.MaxValue)
					);

					a.0.texture = texture;
				}
			}

			t.Finish();
			DeleteDictionaryAndKeysAndValues!(textures);

			for (let pair in MODEL_CACHE) {
				delete pair.key;
				pair.value.Dispose();
			}
			delete MODEL_CACHE;

			//omg.Dispose();
			Log.Info("Loaded block models in {:0.000} ms", sw.Elapsed.TotalMilliseconds);
		}

		private static Json? GetMergedBlockstateJson(Block block) {
			String path = scope $"blockstates/{block.id}.json";
			Json? json = null;

			Meteorite.INSTANCE.resources.ReadJsons(path, scope [&](j) => {
				if (json == null) {
					json = j;
					return;
				}

				if (json.Value.Contains("variants") && j.Contains("variants")) {
					Json variants1 = json.Value["variants"];
					Json variants2 = j["variants"];

					for (let pair in variants2.AsObject) {
						if (variants1.Contains(pair.key)) variants1.Remove(pair.key);

						Json a = pair.value.IsArray ? .Array() : .Object();
						a.Merge(pair.value);
						variants1[pair.key] = a;
					}
				}

				j.Dispose();
			});

			return json;
		}

		private static void ParseElement(Block block, Dictionary<String, List<(Quad, uint16[4])>> textures, Model model, Json modelJson, Json json, Vec3f blockStateRotation) {
			// Parse from
			Json fromJson = json["from"];
			Vec3f from = .((.) fromJson[0].AsNumber / 16, (.) fromJson[1].AsNumber / 16, (.) fromJson[2].AsNumber / 16);

			// Parse to
			Json toJson = json["to"];
			Vec3f to = .((.) toJson[0].AsNumber / 16, (.) toJson[1].AsNumber / 16, (.) toJson[2].AsNumber / 16);

			for (let pair in json["faces"].AsObject) {
				// Parse cull face
				QuadCullFace cullFace = .None;

				if (pair.value.Contains("cullface")) {
					switch (pair.value["cullface"].AsString) {
					case "up": cullFace = .Top;
					case "down": cullFace = .Bottom;
					case "east": cullFace = .East;
					case "west": cullFace = .West;
					case "north": cullFace = .North;
					case "south": cullFace = .South;
					}
				}

				// Get direction. vertices and light
				Direction direction = default;
				Vec3f[4] vertices = .();
				float light = 1;

				switch (pair.key) {
				case "up":
					direction = .Up;
					vertices[0] = .(from.x, to.y, from.z);
					vertices[1] = .(to.x, to.y, from.z);
					vertices[2] = .(to.x, to.y, to.z);
					vertices[3] = .(from.x, to.y, to.z);
				case "down":
					direction = .Down;
					vertices[0] = .(from.x, from.y, from.z);
					vertices[1] = .(from.x, from.y, to.z);
					vertices[2] = .(to.x, from.y, to.z);
					vertices[3] = .(to.x, from.y, from.z);
				case "east":
					direction = .East;
					vertices[0] = .(to.x, from.y, from.z);
					vertices[1] = .(to.x, from.y, to.z);
					vertices[2] = .(to.x, to.y, to.z);
					vertices[3] = .(to.x, to.y, from.z);
				case "west":
					direction = .West;
					vertices[0] = .(from.x, from.y, from.z);
					vertices[1] = .(from.x, to.y, from.z);
					vertices[2] = .(from.x, to.y, to.z);
					vertices[3] = .(from.x, from.y, to.z);
				case "north":
					direction = .North;
					vertices[0] = .(from.x, from.y, from.z);
					vertices[1] = .(to.x, from.y, from.z);
					vertices[2] = .(to.x, to.y, from.z);
					vertices[3] = .(from.x, to.y, from.z);
				case "south":
					direction = .South;
					vertices[0] = .(from.x, from.y, to.z);
					vertices[1] = .(from.x, to.y, to.z);
					vertices[2] = .(to.x, to.y, to.z);
					vertices[3] = .(to.x, from.y, to.z);
				}

				// Get UV
				uint16[4] uv = .(0, 0, 16, 16);

				if (pair.value.Contains("uv")) {
					let uvJson = pair.value["uv"].AsArray;

					uv[0] = (.) uvJson[0].AsNumber;
					uv[1] = (.) uvJson[1].AsNumber;
					uv[2] = (.) uvJson[2].AsNumber;
					uv[3] = (.) uvJson[3].AsNumber;
				}

				// UV Rotation
				if (pair.value.Contains("rotation")) {
					int rotation = (.) pair.value["rotation"].AsNumber;

					uint16 u1 = GetU(uv, GetReverseIndex(0, rotation), rotation);
					uint16 v1 = GetV(uv, GetReverseIndex(0, rotation), rotation);

					uint16 u2 = GetU(uv, GetReverseIndex(2, rotation), rotation);
					uint16 v2 = GetV(uv, GetReverseIndex(2, rotation), rotation);

					/*uint16 n;
					uint16 o;
					if (Math.Sign(j - f) == Math.Sign(l - h)) {
						n = h;
						o = l;
					} else {
						n = l;
						o = h;
					}

					uint16 p;
					uint16 q;
					if (Math.Sign(k - g) == Math.Sign(m - i)) {
						p = i;
						q = m;
					} else {
						p = m;
						q = i;
					}*/

					uv = .(u1, v1, u2, v2);
				}

				// Block state rotation
				/*if (blockStateRotation.y != 0) {
					// Vertices
					Vec3f origin = .(0.5f, 0.5f, 0.5f);
					Mat4 m = Mat4.Identity().Translate(origin).Rotate(.(0, 1, 0), -blockStateRotation.y).Translate(-origin);
	
					for (int i < 4) {
						vertices[i] = .(m * Vec4(vertices[i], 1));
					}

					int count = (int) blockStateRotation.y / 90;
					for (int i < count) {
						//direction = Rotate(direction);

						//if (direction == .Up) Rotate(ref uv);
					}
				}*/

				// Rotation
				if (json.Contains("rotation")) {
					Json rotationJson = json["rotation"];
					Json originJson = rotationJson["origin"];

					Vec3f origin = .(
						(.) originJson.AsArray[0].AsNumber / 16,
						(.) originJson.AsArray[1].AsNumber / 16,
						(.) originJson.AsArray[2].AsNumber / 16
					);

					Vec3f axis = .();
					switch (rotationJson["axis"].AsString) {
					case "x": axis.x = 1;
					case "y": axis.y = 1;
					case "z": axis.z = 1;
					}

					float angle = (.) rotationJson["angle"].AsNumber;

					Mat4 matrix = Mat4.Identity().Translate(origin);

					if (rotationJson.Contains("rescale") && rotationJson["rescale"].AsBool) {
						float scale = Math.Abs(angle) == 22.5f ? MIN_SCALE : MAX_SCALE;
						Vec3f s;

						if (axis.x == 1) s = .(0, 1, 1);
						else if (axis.y == 1) s = .(1, 0, 1);
						else s = .(1, 1, 0);

						matrix = matrix.Scale(.(1, 1, 1) + s * scale);
					}

					matrix = matrix.Rotate(axis, angle).Translate(-origin);

					for (int i < 4) {
						vertices[i] = .(matrix * Vec4(vertices[i], 1));
					}
				}

				// Light
				switch (direction) {
				case .Down: light = 0.4f;
				case .East, .West: light = 0.6f;
				case .North, .South: light = 0.8f;
				default:
				}

				if (!json.GetBool("shade", true)) light = 1;

				// Resolve texture
				String _texture = ResolveTexture(modelJson, pair.value["texture"].AsString);
				if (_texture == null) continue;

				String texture = _texture.Contains(':') ? scope .(_texture.Substring(10)) : _texture;

				List<(Quad, uint16[4])> textureQuads = textures.GetValueOrDefault(texture);
				if (textureQuads == null) {
					textureQuads = new .();
					textures[new .(texture)] = textureQuads;
				}

				// Tint
				bool tint = pair.value.Contains("tintindex");

				// Create quad
				Quad quad = new .(direction, vertices, cullFace, light, tint);
				textureQuads.Add((quad, uv));

				model.Add(quad);
			}
		}

		private static uint16 GetU(uint16[4] uv, int index, int rotation) {
			int i = GetShiftedIndex(index, rotation);
			return uv[i != 0 && i != 1 ? 2 : 0];
		}

		private static uint16 GetV(uint16[4] uv, int index, int rotation) {
			int i = GetShiftedIndex(index, rotation);
			return uv[i != 0 && i != 3 ? 3 : 1];
		}

		private static int GetShiftedIndex(int index, int rotation) => (index + rotation / 90) % 4;
		private static int GetReverseIndex(int index, int rotation) => (index + 4 - rotation / 90) % 4;

		private static Direction Rotate(Direction direction) {
			switch (direction) {
			case .South: return .West;
			case .West: return .North;
			case .North: return .East;
			case .East: return .South;
			default: return direction;
			}
		}

		private static void Rotate<T>(ref T[4] array) {
			T temp = array[0];
			array[0] = array[1];
			array[1] = array[2];
			array[2] = array[3];
			array[3] = temp;
		}

		private static String ResolveTexture(Json json, String name) {
			var name;

			while (name.StartsWith('#')) {
				String key = scope .(name.Substring(1));
				if (!json["textures"].Contains(key)) return null;

				name = json["textures"][key].AsString;
			}

			return name;
		}

		private static List<RawModel> GetMultipartModels(BlockState blockState, Json blockstateJson) {
			List<RawModel> modelJsons = new .();
			String str1 = scope .();
			String str2 = scope .();

			for (Json json in blockstateJson["multipart"].AsArray) {
				bool apply = true;

				if (json.Contains("when")) {
					EvaluateWhen(json["when"], blockState, str1, str2, ref apply);
				}

				if (apply) {
					Json a = json["apply"];
					String b;

					if (a.IsObject) b = a["model"].AsString;
					else b = a[0]["model"].AsString;

					Json json2 = .Object();
					json2["parent"] = .String(b);

					Vec3f rotation = .(
						a.GetInt("x", 0),
						a.GetInt("y", 0),
						a.GetInt("z", 0)
					);

					if (GetMergedModel(json2) case .Ok(let j)) {
						modelJsons.Add(.(j, rotation));
					}
				}
			}

			return modelJsons;
		}

		private static void EvaluateWhen(Json json, BlockState blockState, String str1, String str2, ref bool apply) {
			for (let pair in json.AsObject) {
				if (pair.key == "OR") {
					for (let j in pair.value.AsArray) {
						EvaluateWhen(j, blockState, str1, str2, ref apply);
						if (!apply) break;
					}

					continue;
				}

				blockState.GetProperty(pair.key).GetValueString(str1);
				pair.value.ToString(str2);

				if (str1 != str2) {
					apply = false;
					break;
				}

				str1.Clear();
				str2.Clear();
			}
		}

		private static Result<RawModel> GetVariantModel(Block block, BlockState blockState, Json blockstateJson) {
			// Merge models
			Json a = GetVariant(blockstateJson["variants"], blockState);
			Json variant = a;
			StringView b;

			if (a.IsObject) b = a["model"].AsString;
			else {
				variant = a[0];
				b = variant["model"].AsString;
			}

			Json json = .Object();
			json["parent"] = .String(b);

			switch (GetMergedModel(json)) {
			case .Ok(let j): json = j;
			case .Err: return .Err;
			}

			// Check rotation
			Vec3f rotation = .();

			if (variant.Contains("x")) rotation.x = (.) variant["x"].AsNumber;
			if (variant.Contains("y")) rotation.y = (.) variant["y"].AsNumber;
			if (variant.Contains("z")) rotation.z = (.) variant["z"].AsNumber;
			
			return RawModel(json, rotation);
		}

		private static Result<Json> GetMergedModel(Json json) {
			while (json.Contains("parent")) {
				StringView model = json["parent"].AsString;
				if (model.Contains(':')) model = model.Substring(10);
				StringView modelPath = scope $"models/{model}.json";

				// Remove parent
				json.Remove("parent");

				// Check cache
				String _;
				Json cachedJson;
				if (MODEL_CACHE.TryGet(scope .(modelPath), out _, out cachedJson)) {
					json.Merge(cachedJson);
				} else {
					// Merge and add to cache
					Result<Json> j = Meteorite.INSTANCE.resources.ReadJson(modelPath);

					if (j == .Err) {
						Log.Error("Failed to find model file with path '{}'", modelPath);
						return .Err;
					}

					MODEL_CACHE[new .(modelPath)] = j;
					json.Merge(j);
				}
			}

			return json;
		}

		private static Json GetVariant(Json json, BlockState blockState) {
			List<(Json, Dictionary<StringView, StringView>)> variants = scope .(json.AsObject.Count);

			for (let pair in json.AsObject) {
				Dictionary<StringView, StringView> variant = scope:: .();
				variants.Add((pair.value, variant));
								
				if (pair.key.IsEmpty) continue;

				for (StringView property in pair.key.Split(',')) {
					var e = property.Split('=');
					variant[e.GetNext()] = e.GetNext();
				}
			}

			String str = scope .();

			for (var it = variants.GetEnumerator();;) {
				if (!it.MoveNext()) break;
				let variant = it.Current.1;

				for (let pair in variant) {
					let property = blockState.GetProperty(pair.key);

					str.Clear();
					property.GetValueString(str);

					if (str != pair.value) {
						it.Remove();
						break;
					}
				}
			}

			if (variants.Count > 2) Log.Warning("More than 2 variants left");

			return variants[variants.Count - 1].0;
		}

		private struct RawModel : IDisposable {
			public Json json;
			public Vec3f rotation;

			public this(Json json, Vec3f rotation) {
				this.json = json;
				this.rotation = rotation;
			}

			public void Dispose() {
				json.Dispose();
			}
		}
	}
}