use std::fs::File;
use std::io::Read;
use std::process::Command;

fn main() {
    let mut file = File::open("/etc/init.rc").unwrap();

    let mut string = String::new();
    file.read_to_string(&mut string).unwrap();

    for line_untrimmed in string.lines() {
        let line = line_untrimmed.trim();
        if ! line.is_empty() && ! line.starts_with('#') {
            let args: Vec<&str> = line.split(' ').collect();
            if args.len() > 0 {
                let mut command = Command::new(args[0]);
                for i in 1..args.len() {
                    command.arg(args[i]);
                }

                match command.spawn() {
                    Ok(mut child) => if let Err(err) = child.wait() {
                        println!("init: failed to wait for '{}': {}", line, err);
                    },
                    Err(err) => println!("init: failed to execute '{}': {}", line, err),
                }
            }
        }
    }
}
