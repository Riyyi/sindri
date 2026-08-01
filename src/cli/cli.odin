package cli

import "core:flags"
import "core:fmt"
import "core:os"

Options :: struct {
	verbose:     bool `args:"name=verbose"                        usage:"Enable verbose output"`,
	compression: u8 `args:"name=compression"                      usage:"Compression level, 0-12"`,
	size:        i64 `args:"name=size"                            usage:"Chunk size in bytes"`,
	input:       os.Handle `args:"name=input,file=r,required"     usage:"Path to input directory"`,
	output:      os.Handle `args:"name=output,file=wc"            usage:"Path to ouput directory"`,
	// overflow:    [dynamic]string,
}

parse :: proc() -> Options {
	opts: Options

	err := flags.parse(&opts, os.args[1:], .Unix)

	if err != nil {
		flags.print_errors(typeid_of(Options), err, os.args[0], .Unix)
		os.exit(1)
	}

	if opts.compression > 12 {
		fmt.eprintln("error: compression should be between 0-12")
		os.exit(1)
	}

	return opts
}
