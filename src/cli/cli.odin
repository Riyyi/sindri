package cli

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"

Options :: struct {
	verbose:     bool `args:"name=verbose"                    usage:"Enable verbose output"`,
	compression: u16 `args:"name=compression"                 usage:"Compression level, 0-12"`,
	size:        u64 `args:"name=size"                        usage:"Chunk size in bytes"`,
	input:       ^os.File `args:"name=input,file=r,required"  usage:"Path to input directory"`,
	output:      ^os.File `args:"name=output,file=wc"         usage:"Path to ouput directory"`,
	// overflow:    [dynamic]string,
}

parse :: proc(working_dir: string) -> Options {
	opts: Options

	err := flags.parse(&opts, os.args[1:], .Unix)

	if err != nil {
		flags.print_errors(typeid_of(Options), err, os.args[0], .Unix)
		os.exit(1)
	}

	verify(opts, working_dir)

	return opts
}

@(private)
verify :: proc(opts: Options, working_dir: string) {
	if opts.compression > 12 {
		throw_error(
			`Invalid compression "%d". Compression higher than allowed maximum.`,
			opts.compression,
		)
	}

	input_path := os.name(opts.input)
	if !os.is_dir(input_path) {
		throw_error(`Invalid input "%v". Should be a directory`, input_path)
	}

	if opts.output != nil {
		output_path := os.name(opts.output)
		if !os.is_dir(output_path) {
			throw_error(
				`Invalid output "%v". Should be a directory`,
				output_path,
			)
		}
	}

	if !strings.has_prefix(input_path, working_dir) {
		throw_error(
			`Invalid input "%v". Should be a subdirectory of the working directory.`,
			input_path,
		)
	}
}

@(private)
throw_error :: proc(fmt_str: string, args: ..any) {
	err := flags.Validation_Error {
		message = fmt.tprintf(fmt_str, ..args),
	}
	flags.print_errors(typeid_of(Options), err, os.args[0], .Unix)
	os.exit(1)
}
