use super::*;
use redox::*;

impl Editor {
    pub fn exec(&mut self, Inst(n, cmd): Inst) {
        use super::Key::*;
        use super::Mode::*;
        use super::PrimitiveMode::*;
        use super::CommandMode::*;
        match cmd {
            Ctrl => self.key_state.ctrl = true,
            Alt => self.key_state.alt = true,
            Shift => self.key_state.shift = true,
            _ => {},
        }

        match self.cursor().mode {
            Command(Normal) => match cmd {
                Char('i') => {
                    self.cursor_mut().mode = Mode::Primitive(PrimitiveMode::Insert(
                        InsertOptions {
                            mode: InsertMode::Insert,
                        }));

                },
                Char('h') => self.left(n as usize),
                Char('j') => self.down(n as usize),
                Char('k') => self.up(n as usize),
                Char('l') => self.right(n as usize),
                Char('J') => self.down(15),
                Char('K') => self.up(15),
                Char('x') => self.delete(),
                Char('X') => {
                    self.previous();
                    self.delete();
                },
                Char('$') => self.cursor_mut().x = self.text[self.y()].len(),
                Char('0') => self.cursor_mut().x = 0,
                Char('r') => {
                    loop {
                        if let EventOption::Key(k) = self.window.poll()
                                                     .unwrap_or(Event::new())
                                                     .to_option() {
                            if k.pressed {
                                let x = self.x();
                                let y = self.y();
                                self.text[y][x] = k.character;
                                break;
                            }
                        }
                    }
                },
                Char(' ') if self.key_state.shift => {
                    self.cursor_mut().mode = Mode::Command(CommandMode::Normal);
                },
                Char(' ') => self.next(),
                _ => {},
            },
            Primitive(Insert(_)) => {
                self.insert(cmd);
            },
        }
    }
}