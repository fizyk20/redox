use core::fmt::{self, Write};
use core::result;

use system::syscall::{sys_debug, sys_exit};

pub struct DebugStream;

impl Write for DebugStream {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        let _ = sys_debug(s.as_bytes());

        result::Result::Ok(())
    }
}

#[lang="panic_fmt"]
#[allow(unused_must_use)]
pub extern "C" fn panic_impl(args: fmt::Arguments, file: &'static str, line: u32) -> ! {
    let mut stream = DebugStream;
    fmt::write(&mut stream, args);
    fmt::write(&mut stream, format_args!(" in {}:{}\n", file, line));

    loop {
        let _ = sys_exit(128);
    }
}
