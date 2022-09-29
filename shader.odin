package iris

import "core:os"
import "core:log"
import "core:fmt"
import "core:runtime"
import "core:strings"
import gl "vendor:OpenGL"
import "helios"

Shader :: struct {
	name:             string,
	handle:           u32,
	stages:           Shader_Stages,
	uniforms:         map[string]Shader_Uniform_Info,
	uniform_warnings: map[string]bool,
}

Shader_Stages :: helios.Stages

Shader_Stage :: helios.Stage

@(private)
gl_shader_type :: proc(s: Shader_Stage) -> gl.Shader_Type {
	switch s {
	case .Invalid:
		return .NONE
	case .Fragment:
		return .FRAGMENT_SHADER
	case .Vertex:
		return .VERTEX_SHADER
	case .Geometry:
		return .GEOMETRY_SHADER
	case .Compute:
		return .COMPUTE_SHADER
	case .Tessalation_Eval:
		return .TESS_EVALUATION_SHADER
	case .Tessalation_Control:
		return .TESS_CONTROL_SHADER
	}
	return .SHADER_LINK
}

Uniform_Location :: distinct i32

Shader_Uniform_Info :: struct {
	loc:   Uniform_Location,
	type:  Buffer_Data_Type,
	count: int,
}

Shader_Loader :: union {
	Shader_Builder,
	Raw_Shader_Loader,
}

Shader_Builder :: struct {
	using info:    helios.Builder,
	document_name: string,
	document:      ^helios.Document,
}

Raw_Shader_Loader :: struct {
	name:   string,
	kind:   enum {
		File,
		Byte,
	},
	stages: [len(Shader_Stage)]Maybe(Shader_Stage_Loader),
}

Shader_Stage_Loader :: struct {
	file_path: string,
	source:    string,
}

@(private)
internal_build_shader :: proc(builder: Shader_Builder, allocator := context.allocator) -> Shader {
	output, build_err := helios.build_shader(builder.document, builder, allocator)

	if build_err != nil {
		log.errorf(
			"[%s]: Failed to build shader from document\n\tBuild Options: %#v\n\tError: %#v",
			App_Module.Shader,
			builder.info,
			build_err,
		)
		assert(false)
	}

	loader := Raw_Shader_Loader {
		name = output.name,
		kind = .Byte,
	}
	for stage in helios.Stage {
		if stage in output.active_stages {
			loader.stages[stage] = Shader_Stage_Loader {
				source = output.stages[stage],
			}
		}
	}

	return internal_load_shader_from_bytes(loader, allocator)
}

@(private)
internal_load_shader_from_file :: proc(
	loader: Raw_Shader_Loader,
	allocator := context.allocator,
) -> Shader {
	l := loader
	stage_count: int
	for s, i in l.stages {
		if s != nil {
			stage := s.?
			source, ok := os.read_entire_file(stage.file_path, context.temp_allocator)
			if !ok {
				log.fatalf(
					"%s: Failed to read shader source file:\n\t- %s\n",
					App_Module.IO,
					stage.file_path,
				)
				return {}
			}
			stage.source = string(source)
			l.stages[i] = stage
			stage_count += 1
		}
	}

	if stage_count == 0 {
		assert(false)
	}
	return internal_load_shader_from_bytes(loader)
}

@(private)
internal_load_shader_from_bytes :: proc(
	loader: Raw_Shader_Loader,
	allocator := context.allocator,
) -> (
	shader: Shader,
) {
	if loader.name != "" {
		shader.name = strings.clone(loader.name)
	}

	shader.handle = gl.CreateProgram()
	for s, i in loader.stages {
		if s != nil {
			stage := s.?
			stage_handle := compile_shader_source(
				stage.source,
				gl_shader_type(Shader_Stage(i)),
				loader.name,
			)
			defer gl.DeleteShader(stage_handle)

			if stage_handle == 0 {
				log.debug("Failed to compile fragment shader")
			}
			gl.AttachShader(shader.handle, stage_handle)
		}
	}

	// vertex_handle := compile_shader_source(l.vertex_source, .VERTEX_SHADER, l.name)
	// defer gl.DeleteShader(vertex_handle)
	// fragment_handle := compile_shader_source(l.fragment_source, .FRAGMENT_SHADER, l.name)
	// defer gl.DeleteShader(vertex_handle)

	// switch {
	// case vertex_handle == 0:
	// 	log.debug("Failed to compile fragment shader")
	// case fragment_handle == 0:
	// 	log.debug("Failed to compile fragment shader")
	// }

	// gl.AttachShader(shader.handle, vertex_handle)
	// gl.AttachShader(shader.handle, fragment_handle)
	gl.LinkProgram(shader.handle)
	compile_ok: i32
	gl.GetProgramiv(shader.handle, gl.LINK_STATUS, &compile_ok)
	if compile_ok == 0 {
		max_length: i32
		gl.GetProgramiv(shader.handle, gl.INFO_LOG_LENGTH, &max_length)

		message: [512]byte
		gl.GetProgramInfoLog(shader.handle, 512, &max_length, &message[0])
		log.debugf(
			"%s: Linkage error Shader[%d]:\n\t%s\n",
			App_Module.Shader,
			shader.handle,
			string(message[:max_length]),
		)
	}

	// populate uniform cache
	u_count: i32
	gl.GetProgramiv(shader.handle, gl.ACTIVE_UNIFORMS, &u_count)
	if u_count == 0 {
		return shader
	}
	shader.uniforms = make(
		map[string]Shader_Uniform_Info,
		runtime.DEFAULT_RESERVE_CAPACITY,
		allocator,
	)
	shader.uniform_warnings.allocator = allocator

	max_name_len: i32
	cur_name_len: i32
	size: i32
	type: u32
	gl.GetProgramiv(shader.handle, gl.ACTIVE_UNIFORM_MAX_LENGTH, &max_name_len)
	for i in 0 ..< u_count {
		buf := make([]u8, max_name_len, context.temp_allocator)
		gl.GetActiveUniform(
			shader.handle,
			u32(i),
			max_name_len,
			&cur_name_len,
			&size,
			&type,
			&buf[0],
		)
		u_name := format_uniform_name(buf, cur_name_len, type)
		shader.uniforms[u_name] = Shader_Uniform_Info {
			loc   = Uniform_Location(gl.GetUniformLocation(shader.handle, cstring(raw_data(buf)))),
			type  = uniform_type(type),
			count = int(size),
		}
	}
	return shader
}

@(private)
compile_shader_source :: proc(
	shader_data: string,
	shader_type: gl.Shader_Type,
	filepath: string = "",
) -> (
	shader_handle: u32,
) {
	shader_handle = gl.CreateShader(cast(u32)shader_type)
	shader_data_copy := cstring(raw_data(shader_data))
	gl.ShaderSource(shader_handle, 1, &shader_data_copy, nil)
	gl.CompileShader(shader_handle)

	compile_ok: i32
	gl.GetShaderiv(shader_handle, gl.COMPILE_STATUS, &compile_ok)
	if compile_ok == 0 {
		max_length: i32
		gl.GetShaderiv(shader_handle, gl.INFO_LOG_LENGTH, &max_length)

		message: [512]byte
		file_name: string
		if filepath != "" {
			file_name = filepath
		} else {
			#partial switch shader_type {
			case .VERTEX_SHADER:
				file_name = "Vertex shader"
			case .FRAGMENT_SHADER:
				file_name = "Fragment shader"
			case:
				file_name = "Unknown shader"
			}
		}
		gl.GetShaderInfoLog(shader_handle, 512, &max_length, &message[0])
		log.debugf(
			"[%s]: %s Compilation error [%s]:\n%s\n\nSource:\n",
			App_Module.Shader,
			shader_type,
			file_name,
			string(message[:max_length]),
		)

		lines := strings.split_lines(shader_data, context.temp_allocator)
		for line, i in lines {
			fmt.printf("%d\t%s\n", i + 1, line)
		}
	}
	return
}

@(private = "file")
format_uniform_name :: proc(buf: []u8, l: i32, t: u32, allocator := context.allocator) -> string {
	length := int(l)
	if t == gl.SAMPLER_2D || t == gl.FLOAT_MAT4 {
		if buf[length - 1] == ']' {
			length -= 3
		}
	}
	return strings.clone_from_bytes(buf[:length], allocator)
}

@(private)
uniform_type :: proc(t: u32) -> (type: Buffer_Data_Type) {
	switch t {
	case gl.BOOL:
		type.kind = .Boolean
		type.format = .Scalar

	case gl.INT, gl.SAMPLER_2D, gl.SAMPLER_CUBE:
		type.kind = .Signed_32
		type.format = .Scalar
	case gl.INT_VEC2:
		type.kind = .Signed_32
		type.format = .Vector2
	case gl.INT_VEC3:
		type.kind = .Signed_32
		type.format = .Vector3
	case gl.INT_VEC4:
		type.kind = .Signed_32
		type.format = .Vector4

	case gl.UNSIGNED_INT:
		type.kind = .Unsigned_32
		type.format = .Scalar
	case gl.UNSIGNED_INT_VEC2:
		type.kind = .Unsigned_32
		type.format = .Vector2
	case gl.UNSIGNED_INT_VEC3:
		type.kind = .Unsigned_32
		type.format = .Vector3
	case gl.UNSIGNED_INT_VEC4:
		type.kind = .Unsigned_32
		type.format = .Vector4

	case gl.FLOAT:
		type.kind = .Float_32
		type.format = .Scalar
	case gl.FLOAT_VEC2:
		type.kind = .Float_32
		type.format = .Vector2
	case gl.FLOAT_VEC3:
		type.kind = .Float_32
		type.format = .Vector3
	case gl.FLOAT_VEC4:
		type.kind = .Float_32
		type.format = .Vector4
	case gl.FLOAT_MAT2:
		type.kind = .Float_32
		type.format = .Mat2
	case gl.FLOAT_MAT3:
		type.kind = .Float_32
		type.format = .Mat3
	case gl.FLOAT_MAT4:
		type.kind = .Float_32
		type.format = .Mat4
	}
	return
}

set_shader_uniform :: proc(
	shader: ^Shader,
	name: string,
	value: rawptr,
	caller_loc := #caller_location,
) {
	if exist := name in shader.uniforms; !exist {
		if exist = name in shader.uniform_warnings; !exist {
			log.fatalf(
				"%s: Shader ID[%d]: Failed to retrieve uniform: %s\nCall location: %v",
				App_Module.Shader,
				shader.handle,
				name,
				caller_loc,
			)
			allocator := shader.uniform_warnings.allocator
			shader.uniform_warnings[strings.clone(name, allocator)] = true
		}
		return
	}
	bind_shader(shader)
	info := shader.uniforms[name]
	loc := i32(info.loc)
	switch info.type.format {
	case .Unspecified:
		assert(false)

	case .Scalar:
		#partial switch info.type.kind {
		case .Boolean:
			b := 1 if (cast(^bool)value)^ else 0
			// if b {
			// 	log.debug("????")
			// }
			// log.debugf("at %v: %t", caller_loc, b)
			gl.Uniform1iv(loc, i32(info.count), cast([^]i32)&b)
		case .Signed_32:
			gl.Uniform1iv(loc, i32(info.count), cast([^]i32)value)
		case .Unsigned_32:
			gl.Uniform1uiv(loc, i32(info.count), cast([^]u32)value)
		case .Float_32:
			gl.Uniform1fv(loc, i32(info.count), cast([^]f32)value)
		}

	case .Vector2:
		#partial switch info.type.kind {
		case .Signed_32:
			gl.Uniform2iv(loc, i32(info.count), cast([^]i32)value)
		case .Unsigned_32:
			gl.Uniform2uiv(loc, i32(info.count), cast([^]u32)value)
		case .Float_32:
			gl.Uniform2fv(loc, i32(info.count), cast([^]f32)value)
		}

	case .Vector3:
		#partial switch info.type.kind {
		case .Signed_32:
			gl.Uniform3iv(loc, i32(info.count), cast([^]i32)value)
		case .Unsigned_32:
			gl.Uniform3uiv(loc, i32(info.count), cast([^]u32)value)
		case .Float_32:
			gl.Uniform3fv(loc, i32(info.count), cast([^]f32)value)
		}

	case .Vector4:
		#partial switch info.type.kind {
		case .Signed_32:
			gl.Uniform4iv(loc, i32(info.count), cast([^]i32)value)
		case .Unsigned_32:
			gl.Uniform4uiv(loc, i32(info.count), cast([^]u32)value)
		case .Float_32:
			gl.Uniform4fv(loc, i32(info.count), cast([^]f32)value)
		}

	case .Mat2:
		#partial switch info.type.kind {
		case .Float_32:
			gl.UniformMatrix2fv(loc, i32(info.count), gl.FALSE, cast([^]f32)value)
		}

	case .Mat3:
		#partial switch info.type.kind {
		case .Float_32:
			gl.UniformMatrix3fv(loc, i32(info.count), gl.FALSE, cast([^]f32)value)
		}

	case .Mat4:
		#partial switch info.type.kind {
		case .Float_32:
			gl.UniformMatrix4fv(loc, i32(info.count), gl.FALSE, cast([^]f32)value)
		}
	}
}

destroy_shader :: proc(shader: ^Shader) {
	delete(shader.name)
	for k, _ in shader.uniforms {
		delete(k)
	}
	delete(shader.uniforms)
	gl.DeleteProgram(shader.handle)
}

bind_shader :: proc(shader: ^Shader) {
	gl.UseProgram(shader.handle)
}

dispatch_compute_shader :: proc(shader: ^Shader, dispatch_size: [3]u32) {
	bind_shader(shader)
	defer default_shader()
	gl.DispatchCompute(dispatch_size.x, dispatch_size.y, dispatch_size.z)
	gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT)
}

default_shader :: proc() {
	gl.UseProgram(0)
}
