package iris

import "core:strings"
import "gltf"

Material :: struct {
	name:     string,
	shader:   ^Shader,
	maps:     Material_Maps,
	textures: [len(Material_Map)]^Texture,
}

Material_Loader :: struct {
	name:   string,
	shader: ^Shader,
}

Material_Maps :: distinct bit_set[Material_Map]

Material_Map :: enum byte {
	Diffuse = 0,
	Normal  = 1,
	Shadow  = 2,
}

@(private)
internal_load_empty_material :: proc(loader: Material_Loader) -> Material {
	material := Material {
		name   = strings.clone(loader.name),
		shader = loader.shader,
	}
	return material
}

load_material_from_gltf :: proc(m: gltf.Material) -> ^Material {
	loader := Material_Loader {
		name = m.name,
	}
	resource := material_resource(loader)
	material := resource.data.(^Material)
	if m.base_color_texture.present {
		path := m.base_color_texture.texture.source.reference.(string)
		set_material_map(material, .Diffuse, texture_from_name(path))
	}
	if m.normal_texture.present {
		path := m.normal_texture.texture.source.reference.(string)
		set_material_map(material, .Normal, texture_from_name(path))
	}
	return material
}

set_material_map :: proc(material: ^Material, kind: Material_Map, texture: ^Texture) {
	if kind not_in material.maps {
		material.maps += {kind}
	}
	material.textures[kind] = texture
}

destroy_material :: proc(material: ^Material) {
	delete(material.name)
}