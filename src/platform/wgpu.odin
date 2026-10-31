package platform

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"

import "wgpu:wgpu"

import "sindri:base"

// -----------------------------------------
// Types

// Updated once per frame
Camera_Uniform :: struct {
	mvp: base.Mat4,
}

// Updated once per material
Material_Uniform :: struct {
	dummy: f32,
}

// Updated once per mesh
Renderable_Uniform :: struct {
	transform: base.Mat4,
}

Material :: struct {
	bind_group:     wgpu.BindGroup,
	uniform_buffer: wgpu.Buffer,
}

// TODO: Split Renderable into mesh (vert, idx, #idx) and object (bg, ub)
Renderable :: struct {
	bind_group:     wgpu.BindGroup,
	uniform_buffer: wgpu.Buffer,
	vertex_buffer:  wgpu.Buffer,
	index_buffer:   wgpu.Buffer,
	index_count:    u32,
}

// -----------------------------------------
// Variables

// Instance -> Surface -> Adapter -> Device -> Queue
state: struct {
	ctx:                          runtime.Context,
	os:                           OS,
	// ----------------------------------------
	instance:                     wgpu.Instance, // entry point: creates Adapter, Device and Surface
	surface:                      wgpu.Surface, // handle to a presentable surface (e.g. a window)
	adapter:                      wgpu.Adapter, // handle to physical GPU
	device:                       wgpu.Device, // open connection to a GPU
	queue:                        wgpu.Queue, // handle to command queue on a Device
	config:                       wgpu.SurfaceConfiguration,
	module:                       wgpu.ShaderModule,
	pipeline_layout:              wgpu.PipelineLayout,
	pipeline:                     wgpu.RenderPipeline,
	// ----------------------------------------
	capabilities:                 wgpu.SurfaceCapabilities,
	vsync:                        bool,
	// ----------------------------------------
	depth_texture:                wgpu.Texture,
	depth_texture_view:           wgpu.TextureView,
	// ----------------------------------------
	camera_uniform_buffer:        wgpu.Buffer,
	camera_bind_group_layout:     wgpu.BindGroupLayout,
	camera_bind_group:            wgpu.BindGroup,
	// ----------------------------------------
	material_bind_group_layout:   wgpu.BindGroupLayout,
	materials:                    map[string]Material,
	// ----------------------------------------
	renderable_bind_group_layout: wgpu.BindGroupLayout,
	renderables:                  map[string]Renderable,
	// ----------------------------------------
	diffuse_texture:              wgpu.Texture,
	diffuse_texture_view:         wgpu.TextureView,
	diffuse_sampler:              wgpu.Sampler,
}

// -----------------------------------------
// Constructor/destructor

instance_init :: proc(
	settings: base.Settings,
	allocator := context.allocator,
) {
	state.ctx = context

	state.materials = make(map[string]Material, allocator)
	state.renderables = make(map[string]Renderable, allocator)

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
	wgpu.TextureViewRelease(state.depth_texture_view)
	wgpu.TextureRelease(state.depth_texture)

	wgpu.SamplerRelease(state.diffuse_sampler)
	wgpu.TextureViewRelease(state.diffuse_texture_view)
	wgpu.TextureRelease(state.diffuse_texture)

	wgpu.BufferRelease(state.camera_uniform_buffer)
	wgpu.BindGroupRelease(state.camera_bind_group)
	wgpu.BindGroupLayoutRelease(state.camera_bind_group_layout)

	if state.materials != nil {
		for _, m in state.materials {
			wgpu.BufferRelease(m.uniform_buffer)
			wgpu.BindGroupRelease(m.bind_group)
		}
		delete(state.materials)
	}
	wgpu.BindGroupLayoutRelease(state.material_bind_group_layout)

	if state.renderables != nil {
		for _, r in state.renderables {
			wgpu.BufferRelease(r.uniform_buffer)
			wgpu.BindGroupRelease(r.bind_group)
			wgpu.BufferRelease(r.vertex_buffer)
			wgpu.BufferRelease(r.index_buffer)
		}
		delete(state.renderables)
	}
	wgpu.BindGroupLayoutRelease(state.renderable_bind_group_layout)

	wgpu.RenderPipelineRelease(state.pipeline)
	wgpu.PipelineLayoutRelease(state.pipeline_layout)
	wgpu.ShaderModuleRelease(state.module)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.SurfaceCapabilitiesFreeMembers(state.capabilities)
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

	create_depth_texture()

	// The projection depends on aspect, so rebuild and re-upload the matrix
	upload_camera(
		state.queue,
		state.camera_uniform_buffer,
		framebuffer_aspect(),
	)
}

frame :: proc "c" () {
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
				clearValue = {55 / 255.0, 73 / 255.0, 73 / 255.0, 1},
			},
			depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment {
				view = state.depth_texture_view,
				depthLoadOp = .Clear,
				depthStoreOp = .Store,
				depthClearValue = 1.0,
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.pipeline)

	// Uniform group 0, camera MVP matrix
	wgpu.RenderPassEncoderSetBindGroup(
		render_pass_encoder,
		0,
		state.camera_bind_group,
		dynamicOffsets = nil, // reuse bind group af different byte offsets, per binding
	)

	m := state.materials["dummy"]
	wgpu.RenderPassEncoderSetBindGroup(
		render_pass_encoder,
		1,
		m.bind_group,
		dynamicOffsets = nil, // reuse bind group af different byte offsets, per binding
	)

	// Render all renderables
	for _, r in state.renderables {
		// Uniform group 2
		wgpu.RenderPassEncoderSetBindGroup(
			render_pass_encoder,
			2,
			r.bind_group,
			dynamicOffsets = nil, // reuse bind group af different byte offsets, per binding
		)

		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass_encoder,
			slot = 0,
			buffer = r.vertex_buffer,
			offset = 0, // offset into buffer to start from
			size = wgpu.WHOLE_SIZE, // x bytes of the buffer to use
		)

		wgpu.RenderPassEncoderSetIndexBuffer(
			render_pass_encoder,
			buffer = r.index_buffer,
			format = .Uint16, // type of each element in the buffer
			offset = 0, // offset into buffer to start from
			size = wgpu.WHOLE_SIZE, // x bytes of the buffer to use
		)

		wgpu.RenderPassEncoderDrawIndexed(
			render_pass_encoder,
			r.index_count,
			instanceCount = 1, // draw x instance(s) of the mesh
			firstIndex = 0, // offset into buffer to start from, useful for drawing sub-mesh
			baseVertex = 0, // value added to index before vertex fetch, useful for multi-mesh vertex buffers
			firstInstance = 0, // number to start instance index from
		)

	}

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, {command_buffer})
	wgpu.SurfacePresent(state.surface)
}

create_material :: proc(name: string) {
	if name in state.materials do return

	uniform_buffer := wgpu.DeviceCreateBuffer(
		state.device,
		&{
			label = "material uniform",
			usage = {.Uniform, .CopyDst}, // shader reads, queue writes
			size  = cast(u64)size_of(Material_Uniform),
		},
	)

	uniform := Material_Uniform{}

	// bufferOffset = offset into buffer to start from
	wgpu.QueueWriteBuffer(
		state.queue,
		uniform_buffer,
		0,
		&uniform,
		size_of(Material_Uniform),
	)

	entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0, // slot 0
			buffer  = uniform_buffer,
			offset  = 0, // offset into buffer to start from
			size    = cast(u64)size_of(Material_Uniform),
		},
	}
	bind_group := wgpu.DeviceCreateBindGroup(
		state.device,
		&{
			label = "material bind group",
			layout = state.material_bind_group_layout,
			entryCount = len(entries),
			entries = raw_data(entries[:]),
		},
	)

	state.materials[name] = {
		bind_group     = bind_group,
		uniform_buffer = uniform_buffer,
	}
}

create_renderable :: proc(
	name: string,
	vertices: []base.Vertex,
	indices: []u16,
	first: bool,
) {
	if name in state.renderables do return

	uniform_buffer := wgpu.DeviceCreateBuffer(
		state.device,
		&{
			label = "renderable uniform",
			usage = {.Uniform, .CopyDst}, // shader reads, queue writes
			size  = cast(u64)size_of(Renderable_Uniform),
		},
	)

	transform: base.Mat4
	if first {
		transform = linalg.identity(base.Mat4)
	} else {
		transform = linalg.matrix4_translate(base.Vec3{3, 0, 0})
	}
	uniform := Renderable_Uniform {
		transform = transform,
	}

	// bufferOffset = offset into buffer to start from
	wgpu.QueueWriteBuffer(
		state.queue,
		uniform_buffer,
		0,
		&uniform,
		size_of(Renderable_Uniform),
	)

	entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0, // slot 0
			buffer  = uniform_buffer,
			offset  = 0, // offset into buffer to start from
			size    = cast(u64)size_of(Renderable_Uniform),
		},
	}
	bind_group := wgpu.DeviceCreateBindGroup(
		state.device,
		&{
			label = "renderable bind group",
			layout = state.renderable_bind_group_layout,
			entryCount = len(entries),
			entries = raw_data(entries[:]),
		},
	)

	vertex_buffer := wgpu.DeviceCreateBuffer(
		state.device,
		&{
			label = "vertex buffer",
			usage = {.Vertex, .CopyDst}, // shader reads, queue writes
			size  = cast(u64)(len(vertices) * size_of(base.Vertex)),
		},
	)

	wgpu.QueueWriteBuffer(
		state.queue,
		vertex_buffer,
		0,
		raw_data(vertices),
		cast(uint)(len(vertices) * size_of(base.Vertex)),
	)

	index_buffer := wgpu.DeviceCreateBuffer(
		state.device,
		&{
			label = "index buffer",
			usage = {.Index, .CopyDst}, // shader reads, queue writes
			size  = cast(u64)(len(indices) * size_of(u16)),
		},
	)

	wgpu.QueueWriteBuffer(
		state.queue,
		index_buffer,
		0,
		raw_data(indices),
		cast(uint)(len(indices) * size_of(u16)),
	)

	state.renderables[name] = {
		bind_group     = bind_group,
		uniform_buffer = uniform_buffer,
		vertex_buffer  = vertex_buffer,
		index_buffer   = index_buffer,
		index_count    = cast(u32)len(indices),
	}
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

	// ----------------------------------------
	// Depth buffer

	create_depth_texture()

	// ----------------------------------------
	// Compile shader

	uniforms_struct := to_wgsl_struct(Camera_Uniform, "Camera")
	defer delete(uniforms_struct)
	vertex_input_struct := to_wgsl_struct(
		base.Vertex,
		"VertexInput",
		locations = true,
	)
	defer delete(vertex_input_struct)

	material_struct := to_wgsl_struct(Material_Uniform, "Material")
	defer delete(material_struct)

	renderable_struct := to_wgsl_struct(Renderable_Uniform, "Renderable")
	defer delete(renderable_struct)

	shader := fmt.tprintf(
		`
	%s
	%s
	%s

	@group(0) @binding(0) var<uniform> c: Camera;
	@group(0) @binding(1) var t_diffuse: texture_2d<f32>;
	@group(0) @binding(2) var s_diffuse: sampler;

	@group(1) @binding(0) var<uniform> m: Material;

	@group(2) @binding(0) var<uniform> r: Renderable;

	%s

	struct VertexOutput {{
		@builtin(position) position: vec4<f32>,
		@location(0) col: vec3<f32>,
		@location(1) uv: vec2<f32>,
	}};

	@vertex
	fn vs_main(in: VertexInput) -> VertexOutput {{
		var out: VertexOutput;
		out.position = c.mvp * r.transform * vec4<f32>(in.pos, 1.0);
		out.col = in.col;
		out.uv = in.uv;
		return out;
	}}

	@fragment
	fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {{
		return textureSample(t_diffuse, s_diffuse, in.uv) * vec4<f32>(in.col, 1.0);
	}}
	`,
		uniforms_struct,
		material_struct,
		renderable_struct,
		vertex_input_struct,
	)

	state.module = wgpu.DeviceCreateShaderModule(
		state.device,
		&{
			nextInChain = &wgpu.ShaderSourceWGSL {
				sType = .ShaderSourceWGSL,
				code = shader,
			},
		},
	)

	// ----------------------------------------
	// Camera uniform: buffer, then the baked layout it will be read through

	state.camera_uniform_buffer = wgpu.DeviceCreateBuffer(
		state.device,
		&{
			label = "camera uniform",
			usage = {.Uniform, .CopyDst}, // shader reads, queue writes
			size  = cast(u64)size_of(Camera_Uniform),
		},
	)

	camera_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0, // slot 0
			visibility = {.Vertex},
			buffer = {
				type = .Uniform,
				minBindingSize = cast(u64)size_of(Camera_Uniform),
			},
		},
		{
			binding = 1, // slot 1
			visibility = {.Fragment},
			texture = {
				sampleType = .Float,
				viewDimension = ._2D,
				multisampled = false,
			},
		},
		{
			binding = 2, // slot 2
			visibility = {.Fragment},
			sampler = {type = .Filtering},
		},
	}
	state.camera_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		state.device,
		&{
			label = "camera layout",
			entryCount = len(camera_layout_entries),
			entries = raw_data(camera_layout_entries[:]),
		},
	)

	// ----------------------------------------
	// Material baked layout

	material_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0, // slot 0
			visibility = {.Fragment},
			buffer = {
				type = .Uniform,
				minBindingSize = cast(u64)size_of(Material_Uniform),
			},
		},
	}
	state.material_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		state.device,
		&{
			label = "material layout",
			entryCount = len(material_layout_entries),
			entries = raw_data(material_layout_entries[:]),
		},
	)

	// ----------------------------------------
	// Renderable baked layout

	renderable_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0, // slot 0
			visibility = {.Vertex},
			buffer = {
				type = .Uniform,
				minBindingSize = cast(u64)size_of(Renderable_Uniform),
			},
		},
	}
	state.renderable_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		state.device,
		&{
			label = "renderable layout",
			entryCount = len(renderable_layout_entries),
			entries = raw_data(renderable_layout_entries[:]),
		},
	)

	// ----------------------------------------
	// Diffuse texture + sampler

	state.diffuse_texture, state.diffuse_texture_view, state.diffuse_sampler =
		create_diffuse_texture(state.device, state.queue)

	// ----------------------------------------
	// Buffer shape

	vertex_attributes := to_vertex_attributes(base.Vertex)

	vertex_layout := wgpu.VertexBufferLayout {
			stepMode       = .Vertex,
			arrayStride    = size_of(base.Vertex),
			attributeCount = len(vertex_attributes),
			attributes     = raw_data(vertex_attributes),
		}

	// ----------------------------------------
	// Render pipeline

	group_layouts := [?]wgpu.BindGroupLayout {
		state.camera_bind_group_layout,
		state.material_bind_group_layout,
		state.renderable_bind_group_layout,
	}
	state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		state.device,
		&{
			bindGroupLayoutCount = len(group_layouts),
			bindGroupLayouts = raw_data(group_layouts[:]),
		},
	)

	state.pipeline = wgpu.DeviceCreateRenderPipeline(
		state.device,
		&{
			label = "pipeline",
			layout = state.pipeline_layout,
			vertex = {
				module = state.module,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers = &vertex_layout,
			},
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
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .True,
				depthCompare = .Less,
			},
		},
	)

	// ----------------------------------------
	// Camera bind group

	bind_group_entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0, // slot 0
			buffer  = state.camera_uniform_buffer,
			offset  = 0, // offset into buffer to start from
			size    = cast(u64)size_of(Camera_Uniform),
		},
		{binding = 1, textureView = state.diffuse_texture_view},
		{binding = 2, sampler = state.diffuse_sampler},
	}
	state.camera_bind_group = wgpu.DeviceCreateBindGroup(
		state.device,
		&{
			label = "camera bind group",
			layout = state.camera_bind_group_layout,
			entryCount = len(bind_group_entries),
			entries = raw_data(bind_group_entries[:]),
		},
	)

	// Initial upload of the matrix
	upload_camera(
		state.queue,
		state.camera_uniform_buffer,
		framebuffer_aspect(),
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
	state.capabilities = capabilities

	present_modes := capabilities.presentModes[:capabilities.presentModeCount]
	fmt.println("[wgpu] supported present modes", present_modes)
}

@(private = "file")
pick_present_mode :: proc(vsync: bool) -> wgpu.PresentMode {
	present_modes := state.capabilities.presentModes[:state.capabilities.presentModeCount]

	if len(present_modes) == 0 do return .Fifo

	// Mimmick wgpu auto Vsync behavior
	// https://docs.rs/wgpu/latest/wgpu/enum.PresentMode.html
	if vsync {
		if slice.contains(present_modes, wgpu.PresentMode.FifoRelaxed) {
			return .FifoRelaxed // Adaptive Vsync
		}
	} else {
		if slice.contains(present_modes, wgpu.PresentMode.Immediate) {
			return .Immediate // Vsync Off
		}
		if slice.contains(present_modes, wgpu.PresentMode.Mailbox) {
			return .Mailbox // Fast Vsync
		}
	}

	return .Fifo // Vsync On
}

// Depth buffer: same size as the surface, should get recreated on resize
@(private = "file")
create_depth_texture :: proc() {
	if state.depth_texture != nil {
		wgpu.TextureViewRelease(state.depth_texture_view)
		wgpu.TextureRelease(state.depth_texture)
	}

	state.depth_texture = wgpu.DeviceCreateTexture(
		state.device,
		&{
			label = "depth texture",
			usage = {.RenderAttachment},
			dimension = ._2D,
			size = {
				width = state.config.width,
				height = state.config.height,
				depthOrArrayLayers = 1,
			},
			format = .Depth24Plus,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	state.depth_texture_view = wgpu.TextureCreateView(state.depth_texture, nil)
}

@(private = "file")
framebuffer_aspect :: proc() -> f32 {
	width, height := os_get_framebuffer_size()
	if height == 0 {
		return 1
	}
	return cast(f32)width / cast(f32)height
}

// Perspective projection, WebGPU flavour
@(private = "file")
camera_perspective :: proc(fovy_degrees, aspect, near, far: f32) -> base.Mat4 {
	gl := linalg.matrix4_perspective(
		fovy_degrees * math.PI / 180.0,
		aspect,
		near,
		far,
	)
	// GL's clip space is [-1, 1] and WebGPU's clip space is [0, 1],
	// so fold z with a remap: z' = 1/2 z + 1/2 w
	remap := linalg.identity(base.Mat4)
	remap[2, 2] = 0.5
	remap[2, 3] = 0.5
	return remap * gl
}

@(private = "file")
camera_mvp :: proc(aspect: f32) -> base.Mat4 {
	projection := camera_perspective(60, aspect, 0.1, 100)
	view := linalg.matrix4_look_at_f32({0, 2, 5}, {0, 0, 0}, {0, 1, 0})
	// model = identity: the loader already centered the model at the origin
	return projection * view
}

@(private = "file")
upload_camera :: proc(queue: wgpu.Queue, buffer: wgpu.Buffer, aspect: f32) {
	uniforms := Camera_Uniform {
		mvp = camera_mvp(aspect),
	}
	// bufferOffset = offset into buffer to start from
	wgpu.QueueWriteBuffer(queue, buffer, 0, &uniforms, size_of(Camera_Uniform))
}

// Test 256x256 checkerboard texture, uploaded once
@(private = "file")
create_diffuse_texture :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
) -> (
	wgpu.Texture,
	wgpu.TextureView,
	wgpu.Sampler,
) {
	width, height: u32 = 256, 256
	pixels := make([]u8, width * height * 4)
	defer delete(pixels)

	for y in 0 ..< height {
		for x in 0 ..< width {
			checker := ((x / 32) + (y / 32)) % 2 == 0
			idx := (y * width + x) * 4
			if checker {
				pixels[idx + 0] = 240
				pixels[idx + 1] = 240
				pixels[idx + 2] = 240
				pixels[idx + 3] = 255
			} else {
				pixels[idx + 0] = 64
				pixels[idx + 1] = 64
				pixels[idx + 2] = 64
				pixels[idx + 3] = 255
			}
		}
	}

	texture := wgpu.DeviceCreateTexture(
		device,
		&{
			label = "diffuse texture",
			usage = {.TextureBinding, .CopyDst}, // shader samples, queue writes
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = .RGBA8Unorm,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)

	// Upload texture to GPU
	wgpu.QueueWriteTexture(
		queue,
		&{texture = texture, mipLevel = 0, origin = {0, 0, 0}, aspect = .All}, // destination
		raw_data(pixels),
		len(pixels),
		&{offset = 0, bytesPerRow = width * 4, rowsPerImage = height}, // data layout
		&{width = width, height = height, depthOrArrayLayers = 1}, // 3D extent
	)

	view := wgpu.TextureCreateView(texture, nil)

	sampler := wgpu.DeviceCreateSampler(
		device,
		&{
			addressModeU = .Repeat,
			addressModeV = .Repeat,
			magFilter = .Nearest,
			minFilter = .Nearest,
			mipmapFilter = .Nearest,
			maxAnisotropy = 1,
		},
	)

	return texture, view, sampler
}
