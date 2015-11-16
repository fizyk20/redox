use core::str::StrExt;

use syscall::handle::do_sys_debug;

/// Debug to console
#[macro_export]
macro_rules! debug {
    ($($arg:tt)*) => ({
        $crate::common::debug::d(&format!($($arg)*));
    });
}

/// Debug new line to console
#[macro_export]
macro_rules! debugln {
    ($($arg:tt)*) => ({
        debug!($($arg)*);
        $crate::common::debug::dl();
    });
}

/// Emit a debug string via a syscall
pub fn d(msg: &str) {
    unsafe {
        do_sys_debug(msg.as_ptr(), msg.len());
    }
}

/// Emit a byte as a character to debug output
pub fn db(byte: u8) {
    unsafe {
        do_sys_debug(&byte, 1);
    }
}

/// Convert a nibble (4 bits) to hex (0-9, A-F)
fn nibble_to_hex(nibble: u8) -> Option<u8> {
    if nibble > 16 {
        None
    }
    else if nibble <= 9 {
        Some(nibble + ('0' as u8))
    } 
    else {
        Some(nibble - 10 + ('A' as u8))
    }
}

/// Emit a byte as hex to debug output
pub fn dbh(byte: u8) {
    // First handle the high 4 bits
    let high = nibble_to_hex(byte / 16).unwrap();
    db(high);

    // then the low 4 bits
    let low = nibble_to_hex(byte % 16).unwrap();
    db(low);
}

/// Emit an usize as hex to debug output
pub fn dh(num: usize) {
    if num >= 256 {
        dh(num / 256);
    }
    dbh((num % 256) as u8);
}

/// Emit an usize as decimal to debug output
pub fn dd(num: usize) {
    if num >= 10 {
        dd(num / 10);
    }
    db('0' as u8 + (num % 10) as u8);
}

/// Emit an isize as decimal to debug output
pub fn ds(num: isize) {
    if num >= 0 {
        dd(num as usize);
    } else {
        dc('-');
        dd((-num) as usize);
    }
}

/// Emit a character to debug output
pub fn dc(character: char) {
    db(character as u8);
}

/// Emit a newline to debug output
pub fn dl() {
    dc('\n');
}
