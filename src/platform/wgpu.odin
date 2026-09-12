package platform

import "base:runtime"
import "core:fmt"
import "core:slice"

import "wgpu:wgpu"

import "sindri:core"

// -----------------------------------------
// Variables

// Instance -> Surface -> Adapter -> Device -> Queue
state: struct {
	ctx:             runtime.Context,
	os:              OS,
	// ----------------------------------------
	instance:        wgpu.Instance, // entry point: creates Adapter, Device and Surface
	surface:         wgpu.Surface, // handle to a presentable surface (e.g. a window)
	adapter:         wgpu.Adapter, // handle to physical GPU
	device:          wgpu.Device, // open connection to a GPU
	queue:           wgpu.Queue, // handle to command queue on a Device
	config:          wgpu.SurfaceConfiguration,
	module:          wgpu.ShaderModule,
	pipeline_layout: wgpu.PipelineLayout,
	pipeline:        wgpu.RenderPipeline,
	// ----------------------------------------
	present_modes:   []wgpu.PresentMode,
	vsync:           bool,
}

// -----------------------------------------
// Constructor/destructor

instance_init :: proc(settings: core.Settings) {
	state.ctx = context

	wgpu.SetLogCallback(log_callback, nil)
	wgpu.SetLogLevel(.Warn)

	// Instance
	state.instance = wgpu.CreateInstance(nil)
	if state.instance == nil {
		panic("[wgpu] WebGPU is not supported")
	}

	// Surface
	state.surface = os_get_surface(state.instance)

	// Adapter
	wgpu.InstanceRequestAdapter(
		state.instance,
		&{compatibleSurface = state.surface},
		{callback = on_adapter},
	)

	// Present modes
	get_present_modes()
	state.vsync = settings.vsync

	// Device
	wgpu.AdapterRequestDevice(state.adapter, nil, {callback = on_device})
}

instance_destroy :: proc() {
	wgpu.RenderPipelineRelease(state.pipeline)
	wgpu.PipelineLayoutRelease(state.pipeline_layout)
	wgpu.ShaderModuleRelease(state.module)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)
}

// -----------------------------------------
// Public functions

log_callback :: proc "c" (
	level: wgpu.LogLevel,
	message: string,
	userdata: rawptr,
) {
	context = state.ctx
	fmt.eprintfln("[wgpu:%v] %v", level, message)
}

resize :: proc "c" () {
	context = state.ctx

	if state.surface == nil || state.device == nil do return

	state.config.width, state.config.height = os_get_framebuffer_size()
	wgpu.SurfaceConfigure(state.surface, &state.config)
}

frame :: proc "c" (dt: f32) {
	context = state.ctx

	surface_texture := wgpu.SurfaceGetCurrentTexture(state.surface)
	switch surface_texture.status {
		case .SuccessOptimal, .SuccessSuboptimal:
		// All good, could handle suboptimal here.
		case .Timeout, .Outdated, .Lost:
			// Skip this frame, and re-configure surface.
			if surface_texture.texture != nil {
				wgpu.TextureRelease(surface_texture.texture)
			}
			resize()
			return
		case .Occluded:
			// Window is occluded (e.g. minimized), skip this frame.
			return
		case .Error:
			// Fatal error
			fmt.panicf(
				"[wgpu] triangle get_current_texture status=%v",
				surface_texture.status,
			)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	frame := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(frame)

	command_encoder := wgpu.DeviceCreateCommandEncoder(state.device, nil)
	defer wgpu.CommandEncoderRelease(command_encoder)

	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = frame,
				loadOp = .Clear,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = {0, 1, 0, 1},
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.pipeline)
	wgpu.RenderPassEncoderDraw(
		render_pass_encoder,
		vertexCount = 3,
		instanceCount = 1,
		firstVertex = 0,
		firstInstance = 0,
	)

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, {command_buffer})
	wgpu.SurfacePresent(state.surface)
}

// -----------------------------------------
// Private functions

@(private = "file")
on_adapter :: proc "c" (
	status: wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: string,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	context = state.ctx
	if status != .Success || adapter == nil {
		fmt.panicf("[wgpu] request adapter failure: [%v] %s", status, message)
	}
	state.adapter = adapter
}

@(private = "file")
on_device :: proc "c" (
	status: wgpu.RequestDeviceStatus,
	device: wgpu.Device,
	message: string,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	context = state.ctx
	if status != .Success || device == nil {
		fmt.panicf("[wgpu] request device failure: [%v] %s", status, message)
	}
	state.device = device

	state.queue = wgpu.DeviceGetQueue(state.device)

	width, height := os_get_framebuffer_size()

	state.config = wgpu.SurfaceConfiguration {
		device      = state.device,
		usage       = {.RenderAttachment},
		format      = .BGRA8Unorm,
		width       = width,
		height      = height,
		presentMode = pick_present_mode(state.vsync),
		alphaMode   = .Opaque,
	}
	wgpu.SurfaceConfigure(state.surface, &state.config)

	shader :: `
	@vertex
	fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4<f32> {
		let x = f32(i32(in_vertex_index) - 1);
		let y = f32(i32(in_vertex_index & 1u) * 2 - 1);
		return vec4<f32>(x, y, 0.0, 1.0);
	}

	@fragment
	fn fs_main() -> @location(0) vec4<f32> {
		return vec4<f32>(1.0, 0.0, 0.0, 1.0);
	}`

	state.module = wgpu.DeviceCreateShaderModule(
		state.device,
		&{
			nextInChain = &wgpu.ShaderSourceWGSL {
				sType = .ShaderSourceWGSL,
				code = shader,
			},
		},
	)

	state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(state.device, &{})
	state.pipeline = wgpu.DeviceCreateRenderPipeline(
		state.device,
		&{
			layout = state.pipeline_layout,
			vertex = {module = state.module, entryPoint = "vs_main"},
			fragment = &{
				module = state.module,
				entryPoint = "fs_main",
				targetCount = 1,
				targets = &wgpu.ColorTargetState {
					format = .BGRA8Unorm,
					writeMask = wgpu.ColorWriteMaskFlags_All,
				},
			},
			primitive = {topology = .TriangleList},
			multisample = {count = 1, mask = 0xFFFFFFFF},
		},
	)
}

@(private = "file")
get_present_modes :: proc() {
	capabilities, status := wgpu.SurfaceGetCapabilities(
		state.surface,
		state.adapter,
	)
	if status != .Success {
		fmt.panicf("[wgpu] surface capabilities failure: [%v]", status)
	}
	state.present_modes = capabilities.presentModes[:capabilities.presentModeCount]
	fmt.println("[wgpu] supported present modes", state.present_modes)
}

@(private = "file")
pick_present_mode :: proc(vsync: bool) -> wgpu.PresentMode {
	if len(state.present_modes) == 0 do return .Fifo

	// Mimmick wgpu auto Vsync behavior
	// https://docs.rs/wgpu/latest/wgpu/enum.PresentMode.html
	if vsync {
		if slice.contains(state.present_modes, wgpu.PresentMode.FifoRelaxed) {
			return .FifoRelaxed // Adaptive Vsync
		}
	} else {
		if slice.contains(state.present_modes, wgpu.PresentMode.Immediate) {
			return .Immediate // Vsync Off
		}
		if slice.contains(state.present_modes, wgpu.PresentMode.Mailbox) {
			return .Mailbox // Fast Vsync
		}
	}

	return .Fifo // Vsync On
}
