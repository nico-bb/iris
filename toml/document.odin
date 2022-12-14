package toml

Document :: struct {
	keys: map[string]string,
	root: Table,
}

Value :: union {
	Nil,
	Float,
	String,
	Boolean,
	Array,
	Table,
}

Nil :: struct {}
String :: string
Float :: f64
Boolean :: bool
Array :: distinct [dynamic]Value
Table :: distinct map[string]Value

Key :: union {
	Bare_Key,
	Dotted_Key,
}

Bare_Key :: string

Dotted_Key :: struct {
	data: Bare_Key,
	next: ^Key,
}
