package obj

import "core:strconv"

Vertex_Data :: distinct []f32
Index_Data :: distinct []u32

Parser :: struct {
	source:  string,
	current: int,
}

Obj_Error :: enum {
	OK,
	Malformed_Number,
}

parse_obj :: proc(source: string, allocator := context.allocator) {
	positions: [dynamic][3]f32
	positions.allocator = context.temp_allocator
	uvs: [dynamic][2]f32
	uvs.allocator = context.temp_allocator
	normals: [dynamic][3]f32
	normals.allocator = context.temp_allocator

	p := Parser {
		source = source,
	}
	parse: for {
		c := advance(&p)
		if c == EOF {
			break parse
		}

		switch c {
		case 'v':
			n := peek(&p)
			switch n {
			case 't':
				skip_whitespaces(&p)
			case 'n':
				skip_whitespaces(&p)
			case ' ':
				skip_whitespaces(&p)
			case:
				assert(false)
			}
		case 'f':
		}
	}
}

EOF: byte : 0

@(private)
advance :: proc(p: ^Parser) -> byte {
	p.current += 1
	if p.current >= len(p.source) {
		return EOF
	}
	return p.source[p.current - 1]
}

@(private)
peek :: proc(p: ^Parser) -> byte {
	if p.current >= len(p.source) {
		return EOF
	}
	return p.source[p.current]
}

@(private)
skip_whitespaces :: proc(p: ^Parser) {
	for {
		c := peek(p)
		if c != EOF && (c == ' ' || c == '\r' || c == '\t') {
			advance(p)
		} else {
			break
		}
	}
}

@(private)
parse_float :: proc(p: ^Parser) -> (n: f32, err: Obj_Error) {
	has_decimal := false
	start := p.current
	signed: bool
	sign := peek(p)
	if sign == '-' {
		signed = true
	}
	parse: for {
		c := peek(p)
		if c != EOF {
			switch c {
			case '0' ..= '9':
				advance(p)
			case '.':
				if !has_decimal {
					has_decimal = true
					advance(p)
				} else {
					assert(false)
				}
			case ' ':
				break parse
			case:
				assert(false)
			}
		} else {
			break parse
		}
	}
	ok: bool
	n, ok = strconv.parse_f32(p.source[start:p.current])
	if !ok {
		err = .Malformed_Number
	}
	if signed {
		n = -n
	}
	return
}

@(private)
parse_int :: proc(p: ^Parser) -> (n: u32) {
	start := p.current
	parse: for {
		c := peek(p)
		if c != EOF {
			switch c {
			case '0' ..= '9':
				advance(p)
			case ' ':
				break parse
			case:
				assert(false)
			}
		} else {
			break parse
		}
	}
	number, ok := strconv.parse_uint(p.source[start:p.current])
	n = u32(number)
	return
}
