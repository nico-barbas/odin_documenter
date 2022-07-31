package main

import "lib/odin/format"
import "lib/odin/printer"

import "core:os"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:odin/parser"
import "core:odin/ast"

FILEPATH :: "tests\\main.odin"
OUTPUT :: "tests\\main.odin_document"

main :: proc() {
	using printer

	init_global_temporary_allocator(mem.Megabyte * 100)
	source, _ := os.read_entire_file(FILEPATH, context.temp_allocator)

	config := default_style
	config.max_characters = 80
	config.newline_style = .LF

	pkg := ast.Package {
		kind = .Normal,
	}

	file := ast.File {
		pkg      = &pkg,
		src      = string(source),
		fullpath = FILEPATH,
	}

	allocator := context.temp_allocator

	prser := parser.default_parser(parser.Flags{.Optional_Semicolons})

	ok := parser.parse_file(&prser, &file)

	p := make_printer(config, allocator)

	p.comments = file.comments
	p.string_builder = strings.builder_make(p.allocator)
	p.src = file.src
	context.allocator = p.allocator

	if p.config.tabs {
		p.indentation = "\t"
		p.indentation_width = p.config.tabs_width
	} else {
		p.indentation = strings.repeat(" ", p.config.spaces)
		p.indentation_width = p.config.spaces
	}

	if p.config.newline_style == .CRLF {
		p.newline = "\r\n"
	} else {
		p.newline = "\n"
	}

	build_disabled_lines_info(&p)

	p.source_position.line = 1
	p.source_position.column = 1

	p.document = move_line(&p, file.pkg_token.pos)
	p.document = cons(
		p.document,
		cons_with_nopl(text(file.pkg_token.text), text(file.pkg_name)),
	)

	for decl in file.decls {
		p.document = cons(p.document, visit_decl(&p, cast(^ast.Decl)decl))
	}

	if len(p.comments) > 0 {
		infinite := p.comments[len(p.comments) - 1].end
		infinite.offset = 9999999
		document, _ := visit_comments(&p, infinite)
		p.document = cons(p.document, document)
	}

	p.document = cons(p.document, newline(1))

	structure := visit_doc(p.document, {.Add_Comma, .Enforce_Newline})

	p.document = structure

	list := make([dynamic]Tuple, p.allocator)
	append(&list, Tuple{document = p.document, indentation = 0})

	format(p.config.max_characters, &list, &p.string_builder, &p)

	out := strings.to_string(p.string_builder)
	os.write_entire_file(fmt.tprintf(OUTPUT), transmute([]u8)out)
}

DEFAULT_DOC_OPTIONS :: printer.List_Options{.Add_Comma, .Enforce_Newline}
INLINE_DOC_OPTIONS :: printer.List_Options{}

visit_doc :: proc(
	d: ^printer.Document,
	options := DEFAULT_DOC_OPTIONS,
) -> (
	result: ^printer.Document,
) {
	using printer

	switch v in d {
	case Document_Nil:
		result = text("nil")

	case Document_Newline:
		result = text("newline")

	case Document_Text:
		result = cons(text(`"`), text(v.value), text(`"`))

	case Document_Nest:
		result = cons(
			text("indent("),
			nest(cons(newline(1), visit_doc(v.document))),
			newline(1),
			text(")"),
		)

	case Document_Break:
		result = cons(text(`"`), text(v.value), text(`"`))

	case Document_Group:
		result = cons(
			text("group="),
			text(`"`),
			text(v.options.id),
			text(`"`),
			text("("),
			visit_doc(v.document),
			text(")"),
		)

	case Document_Cons:
		length := 0
		at := 0
		for elem, i in v.elements {
			if elem == nil {
				continue
			}
			length += 1
			at = i
		}
		if length == 1 {
			result = visit_doc(v.elements[at])
		} else {
			c := Document_Cons{}
			c.elements = make([]^Document, length)
			index := 0
			for elem, i in v.elements {
				if elem == nil {
					continue
				}
				last_elem := index == length - 1
				inner_options := options + {.Enforce_Newline}
				if .Add_Comma in options {
					c.elements[index] = cons(visit_doc(elem, inner_options), text(","))
				} else {
					c.elements[index] = visit_doc(elem, inner_options)
				}

				if !last_elem {
					c.elements[index] = cons(c.elements[index], newline(1))
				}
				index += 1
			}
			inners := empty()
			inners^ = c
			if .Enforce_Newline in options {
				result = cons(
					text("["),
					nest(cons(newline(1), inners)),
					newline(1),
					text("]"),
				)
			} else {
				result = cons(text("["), inners, text("]"))
			}
		}


	case Document_If_Break:
		result = cons_with_nopl(text("if_break =>"), cons(text(`"`), text(v.value), text(`"`)))


	case Document_Align:
		result = cons_with_nopl(text("align =>"), visit_doc(v.document))


	case Document_Nest_If_Break:
		result = cons_with_nopl(text("nest_if_break =>"), visit_doc(v.document))

	case Document_Break_Parent:
		result = empty()


	case Document_Line_Suffix:
		result = cons(text(`"`), text(v.value), text(`"`))

	}

	return
}
