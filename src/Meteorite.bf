using System;
using System.IO;
using System.Collections;

using Cacti;
using Cacti.Graphics;
using Bulkan;

namespace Meteorite;

class Meteorite : Application {
	public static Meteorite INSTANCE;

	public Options options ~ delete _;
	public ResourceLoader resources ~ delete _;
	public TextureManager textures ~ delete _;

	public Camera camera ~ delete _;
	public RenderTickCounter tickCounter ~ delete _;

	public GameRenderer gameRenderer;
	public LightmapManager lightmapManager;
	public WorldRenderer worldRenderer;
	public BlockEntityRenderDispatcher blockEntityRenderDispatcher;
	public EntityRenderDispatcher entityRenderDispatcher;
	public TextRenderer textRenderer;
	public HudRenderer hud;

	public ServerManager servers;
	public AccountManager accounts;

	public ClientConnection connection;
	public World world;
	public ClientPlayerEntity player;

	private Screen screen;
	private List<ITask> tasks = new .() ~ DeleteContainerAndItems!(_);

	private GpuImage swapchainTarget;
	private bool afterScreenshot;
	
	[Tracy.Profile]
	public this() : base("Meteorite") {
		INSTANCE = this;
		Directory.CreateDirectory("run");

		options = new .();

		resources = new .();
		Gfxa.Init();

		textures = new .();

		camera = new .(window);
		tickCounter = new .(20, 0);

		EntityTypes.Register();

		gameRenderer = new .();
		lightmapManager = new .();
		blockEntityRenderDispatcher = new .();
		entityRenderDispatcher = new .();
		textRenderer = new .();
		hud = new .();

		servers = new .();
		accounts = new .();

		camera.pos.y = 160;
		camera.yaw = 45;

		I18N.Load();
		VoxelShapes.Init();
		Blocks.Register();
		Items.Register();
		BlockModelLoader.LoadModels();
		Biomes.Register();
		ChatTypes.Register();
		Biome.LoadColormaps();
		Buffers.CreateGlobalIndices();
		SkyRenderer.Init();
		BlockColors.Init();
		FrameUniforms.Init();

		Input.keyEvent.Add(new (key, scancode, action) => {
			if (world == null || player == null || Input.capturingCharacters || action != .Release) return false;

			if (key == .O) {
				if (Screen is OptionsScreen) Screen = null;
				else Screen = new OptionsScreen();

				return true;
			}

			if (key == .R) {
				Log.Info("Reloading shaders");

				if (Gfx.Shaders.Reload() == .Err) {
					Log.Error("Failed to reload shaders");
				}

				return true;
			}

			return false;
		});

		Input.scrollEvent.Add(new (scroll) => {
			if (world == null || player == null) return false;

			Meteorite me = .INSTANCE;

			me.player.inventory.selectedSlot -= (.) scroll;

			if (me.player.inventory.selectedSlot < 0) me.player.inventory.selectedSlot = 8;
			else if (me.player.inventory.selectedSlot > 8) me.player.inventory.selectedSlot = 0;

			me.connection.Send(scope SetSelectedSlotC2SPacket(me.player.inventory.selectedSlot));

			return true;
		});

		window.MouseHidden = true;
		Screen = new MainMenuScreen();
	}

	public ~this() {
		// Rendering needs to be deleted before Gfx is shut down
		delete screen;
		delete hud;
		delete textRenderer;
		delete entityRenderDispatcher;
		delete blockEntityRenderDispatcher;
		delete worldRenderer;
		delete lightmapManager;
		delete gameRenderer;

		FrameUniforms.Destroy();
		SkyRenderer.Destroy();
		Buffers.Destroy();
		Gfxa.Destroy();

		delete servers;
		delete accounts;

		// Connection needs to be deleted before world
		delete connection;
		delete world;
	}

	public void Join(StringView ip, int32 port, StringView hostname) {
		Runtime.Assert(accounts.active != null);
		Tracy.Message(scope $"Join: {hostname} ({ip}:{port})");

		connection = new .(ip, port, hostname);

		if (connection.Start() == .Ok) {
			Screen = null;
		}
		else {
			Log.Error("Failed to connect to {}:{}", connection.ip, connection.port);
			DeleteAndNullify!(connection);
		}
	}

	public void Disconnect(Text reason) {
		if (connection == null) return;
		Tracy.Message(scope $"Disconnect: {reason}");

		DeleteAndNullify!(worldRenderer);
		DeleteAndNullify!(world);
		player = null;
		DeleteAndNullify!(connection);

		Screen = new MainMenuScreen();

		Log.Info("Disconnected: {}", reason);
	}

	public Screen Screen {
		get => screen;
		set {
			screen?.Close();
			delete screen;

			screen = value;
			screen?.Open();
		}
	}

	public void Execute(ITask task) => tasks.Add(task);
	public void Execute(delegate void() task) => tasks.Add(new DelegateTask(task));

	[Tracy.Profile]
	private void Tick(float tickDelta) {
		if (connection != null && connection.closed) {
			DeleteAndNullify!(connection);
			window.MouseHidden = false;
		}

		for (let task in tasks) {
			task.Run();
			delete task;
		}
		
		tasks.Clear();

		if (world == null) return;

		world.Tick();

		textures.Tick();

		if (!window.minimized) gameRenderer.Tick();
	}
	
	[Tracy.Profile]
	protected override void Update(double delta) {
		Screenshots.Update();

		if (player != null && window.MouseHidden) player.Turn(Input.mouseDelta);

		int tickCount = tickCounter.BeginRenderTick();
		for (int i < Math.Min(10, tickCount)) Tick(tickCounter.tickDelta);
	}
	
	[Tracy.Profile]
	protected override void Render(List<CommandBuffer> commandBuffers, GpuImage target, double delta) {
		if (!window.minimized) {
			CommandBuffer cmds = Gfx.CommandBuffers.GetBuffer();
			commandBuffers.Add(cmds);

			gameRenderer.Render(cmds, target, (.) delta);
		}
	}
	
	[Tracy.Profile]
	protected override CommandBuffer AfterRender(GpuImage target) {
		if (Screenshots.rendering) {
			CommandBuffer cmds = Gfx.CommandBuffers.GetBuffer();

			cmds.Begin();
			cmds.PushDebugGroup("Screenshot");

			cmds.CopyImageToBuffer(target, Screenshots.buffer);
			cmds.BlitImage(Screenshots.texture, swapchainTarget);

			cmds.PopDebugGroup();
			cmds.End();

			afterScreenshot = true;
			return cmds;
		}

		return null;
	}
	
	[Tracy.Profile]
	protected override GpuImage GetTargetImage(VkSemaphore imageAvailableSemaphore) {
		if (afterScreenshot) {
			Screenshots.Save();
			afterScreenshot = false;
		}
		
		swapchainTarget = Gfx.Swapchain.GetImage(imageAvailableSemaphore);
		return Screenshots.rendering ? Screenshots.texture : swapchainTarget;
	}
}