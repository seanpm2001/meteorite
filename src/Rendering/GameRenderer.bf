using System;
using System.Collections;

using Cacti;
using ImGui;

namespace Meteorite {
	class GameRenderer {
		private Meteorite me = .INSTANCE;

		private List<GpuImage> images = new .() ~ DeleteContainerAndItems!(_);

		public GpuImage mainColor, mainNormal;
		public GpuImage mainDepth;
		public GpuImage smaaEdges, smaaBlend;

		public DescriptorSet mainColorSet ~ delete _, mainNormalSet ~ delete _, mainDepthSet ~ delete _;
		public DescriptorSet smaaEdgesSet ~ delete _, smaaBlendSet ~ delete _;

		private GpuImage smaaArea ~ delete _, smaaSearch ~ delete _;
		private DescriptorSet smaaAreaSet ~ delete _, smaaSearchSet ~ delete _;

		private SSAO ssao ~ delete _;

		private float delta;
		private bool afterScreenshot;

		public this() {
			mainColor = ColorImage("Main Color");
			mainNormal = ColorImage("Main Normal", .RGBA16);
			mainDepth = DepthImage("Main Depth");

			mainColorSet = Gfx.DescriptorSets.Create(Gfxa.IMAGE_SET_LAYOUT, .SampledImage(mainColor, .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, Gfxa.LINEAR_SAMPLER));
			mainNormalSet = Gfx.DescriptorSets.Create(Gfxa.IMAGE_SET_LAYOUT, .SampledImage(mainNormal, .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, Gfxa.NEAREST_SAMPLER));
			mainDepthSet = Gfx.DescriptorSets.Create(Gfxa.IMAGE_SET_LAYOUT, .SampledImage(mainDepth, .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, Gfxa.NEAREST_SAMPLER));

			Input.keyEvent.Add(new => OnKey, -10);
		}

		private bool OnKey(Key key, int scancode, InputAction action) {
			if (action != .Press) return false;

			if (key == .Escape) {
				if (me.Screen != null) me.Screen = null;
				else me.window.MouseHidden = !me.window.MouseHidden;

				return true;
			}

			return false;
		}

		public void Tick() {
			me.lightmapManager.Tick();
		}
		
		public void Render(CommandBuffer cmds, GpuImage target, float delta) {
			this.delta = delta;

			FrameUniforms.Update();
			me.lightmapManager.Update(delta);

			if (me.options.ao.HasSSAO && ssao == null) ssao = new .(ColorImage("SSAO", .R8));

			for (GpuImage image in images)
				image.Resize(target.size);

			cmds.Begin();
			cmds.SetViewport(target.size, true, true);

			Color clearColor = me.world != null ? me.world.GetClearColor(me.camera, me.tickCounter.tickDelta) : .(200, 200, 200, 255);
			bool world = me.world != null && me.worldRenderer != null;

			if (world) {
				SetupWorldRendering();

				{
					// Main Pre
					cmds.PushDebugGroup("Main - Pre");
					cmds.BeginPass(.(mainDepth, 1), .(mainColor, clearColor));

					RenderMainPre(cmds);

					cmds.EndPass();
					cmds.PopDebugGroup();
				}
				{
					// Main
					cmds.PushDebugGroup("Main");
					cmds.BeginPass(.(mainDepth, null), .(mainColor, null), .(mainNormal, .ZERO));

					RenderMain(cmds);

					cmds.EndPass();
					cmds.PopDebugGroup();
				}
				{
					// Main Post
					cmds.PushDebugGroup("Main - Post");
					cmds.BeginPass(.(mainDepth, null), .(mainColor, null));

					RenderMainPost(cmds);

					cmds.EndPass();
					cmds.PopDebugGroup();
				}

				if (me.options.ao.HasSSAO) {
					// SSAO
					ssao.Render(cmds);
				}

				if (me.options.aa.enabled) {
					// SMAA
					if (smaaEdges == null) {
						smaaEdges = ColorImage("SMAA - Edges", .RG8);
						smaaBlend = ColorImage("SMAA - Blend");

						smaaEdgesSet = Gfx.DescriptorSets.Create(Gfxa.IMAGE_SET_LAYOUT, .SampledImage(smaaEdges, .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, Gfxa.LINEAR_SAMPLER));
						smaaBlendSet = Gfx.DescriptorSets.Create(Gfxa.IMAGE_SET_LAYOUT, .SampledImage(smaaBlend, .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, Gfxa.LINEAR_SAMPLER));

						smaaArea = Gfxa.CreateImage("SMAA_AreaTex.png");
						smaaSearch = Gfxa.CreateImage("SMAA_SearchTex.png");

						smaaAreaSet = Gfx.DescriptorSets.Create(Gfxa.IMAGE_SET_LAYOUT, .SampledImage(smaaArea, .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, Gfxa.LINEAR_SAMPLER));
						smaaSearchSet = Gfx.DescriptorSets.Create(Gfxa.IMAGE_SET_LAYOUT, .SampledImage(smaaSearch, .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, Gfxa.LINEAR_SAMPLER));
					}

					// SMAA - Edge Detection
					cmds.TransitionImage(mainColor, .Sample);
					cmds.TransitionImage(smaaEdges, .ColorAttachment);
					cmds.PushDebugGroup("SMAA - Edge Detection");
					cmds.BeginPass(null, .(smaaEdges, .ZERO));

					RenderSmaaEdgeDetection(cmds);

					cmds.EndPass();
					cmds.PopDebugGroup();

					// SMAA - Blending
					cmds.TransitionImage(smaaEdges, .Sample);
					cmds.TransitionImage(smaaBlend, .ColorAttachment);
					cmds.PushDebugGroup("SMAA - Blending");
					cmds.BeginPass(null, .(smaaBlend, .ZERO));

					RenderSmaaBlending(cmds);

					cmds.EndPass();
					cmds.PopDebugGroup();
				}

				{
					// Post
					cmds.TransitionImage(mainColor, .Sample);
					if (me.options.aa.enabled) cmds.TransitionImage(smaaBlend, .Sample);
					if (ssao != null) ssao.Transition(cmds);

					cmds.PushDebugGroup("Post");
					cmds.BeginPass(null, .(target, .ZERO));

					RenderPost(cmds);

					cmds.EndPass();
					cmds.PopDebugGroup();
				}
			}

			// 2D
			if (!Screenshots.rendering || Screenshots.options.includeGui) {
				Color? clear = null;
				if (!world) clear = clearColor;
			
				cmds.PushDebugGroup("2D");
				cmds.BeginPass(null, .(target, clear));

				Render2D(cmds);

				cmds.EndPass();
				cmds.PopDebugGroup();
			}

			cmds.End();
		}
		
		private void SetupWorldRendering() {
			if (me.player != null/* && me.player.gamemode == .Spectator*/) {
				Vec3d pos = me.player.lastPos.Lerp(me.tickCounter.tickDelta, me.player.pos);
				me.camera.pos = .((.) (pos.x), (.) pos.y + 1.62f, (.) (pos.z));
				me.camera.yaw = me.player.yaw;
				me.camera.pitch = me.player.pitch;
			}
			/*else {
				if (!Input.capturingCharacters) me.camera.FlightMovement(delta);
			}*/

			me.camera.fov = me.options.fov;
			me.camera.Update(me.options.renderDistance * Section.SIZE * 4);
		}
		
		private void RenderMainPre(CommandBuffer cmds) {
			me.worldRenderer.RenderPre(cmds, me.tickCounter.tickDelta, delta);
		}
		
		private void RenderMain(CommandBuffer cmds) {
			me.worldRenderer.Render(cmds, me.tickCounter.tickDelta, delta);
		}
		
		private void RenderMainPost(CommandBuffer cmds) {
			me.worldRenderer.RenderPost(cmds, me.tickCounter.tickDelta, delta);
		}

		private void RenderSmaaEdgeDetection(CommandBuffer cmds) {
			cmds.Bind(Gfxa.SMAA_EDGE_DETECTION_PIPELINE);
			FrameUniforms.Bind(cmds);
			cmds.Bind(mainColorSet, 1);

			MeshBuilder mb = scope .();

			mb.Quad(
				mb.Vertex<PostVertex>(.(.(-1, -1), .(0, 1))),
				mb.Vertex<PostVertex>(.(.(-1, 1), .(0, 0))),
				mb.Vertex<PostVertex>(.(.(1, 1), .(1, 0))),
				mb.Vertex<PostVertex>(.(.(1, -1), .(1, 1)))
			);

			cmds.Draw(mb.End());
		}

		private void RenderSmaaBlending(CommandBuffer cmds) {
			cmds.Bind(Gfxa.SMAA_BLENDING_PIPELINE);
			FrameUniforms.Bind(cmds);
			cmds.Bind(smaaEdgesSet, 1);
			cmds.Bind(smaaAreaSet, 2);
			cmds.Bind(smaaSearchSet, 3);

			MeshBuilder mb = scope .();

			mb.Quad(
				mb.Vertex<PostVertex>(.(.(-1, -1), .(0, 1))),
				mb.Vertex<PostVertex>(.(.(-1, 1), .(0, 0))),
				mb.Vertex<PostVertex>(.(.(1, 1), .(1, 0))),
				mb.Vertex<PostVertex>(.(.(1, -1), .(1, 1)))
			);

			cmds.Draw(mb.End());
		}
		
		private void RenderPost(CommandBuffer cmds) {
			cmds.Bind(Gfxa.POST_PIPELINE);
			FrameUniforms.Bind(cmds);
			cmds.Bind(mainColorSet, 1);

			if (me.options.ao.HasSSAO) ssao.Bind(cmds, 2);
			else cmds.Bind(Gfxa.PIXEL_SET, 2);

			if (me.options.aa.enabled) cmds.Bind(smaaBlendSet, 3);

			MeshBuilder mb = scope .();

			mb.Quad(
				mb.Vertex<PostVertex>(.(.(-1, -1), .(0, 1))),
				mb.Vertex<PostVertex>(.(.(-1, 1), .(0, 0))),
				mb.Vertex<PostVertex>(.(.(1, 1), .(1, 0))),
				mb.Vertex<PostVertex>(.(.(1, -1), .(1, 1)))
			);

			cmds.Draw(mb.End());
		}

		private void Render2D(CommandBuffer cmds) {
			if (ImGuiCacti.NewFrame()) {
				if (me.world != null && me.player != null) me.hud.Render(cmds, delta);

				me.Screen?.Render();
			}
		}

		private GpuImage ColorImage(StringView name, ImageFormat format = .BGRA) {
			GpuImage image = Gfx.Images.Create(format, .ColorAttachment, .(1280, 720), name);
			images.Add(image);
			return image;
		}

		private GpuImage DepthImage(StringView name) {
			GpuImage image = Gfx.Images.Create(.Depth, .DepthAttachment, .(1280, 720), name);
			images.Add(image);
			return image;
		}
	}
}