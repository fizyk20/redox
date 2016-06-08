use collections::vec_deque::VecDeque;

use core::cell::UnsafeCell;
use core::mem;
use core::ops::DerefMut;

use super::WaitCondition;

pub struct WaitQueue<T> {
    pub inner: UnsafeCell<VecDeque<T>>,
    pub condition: WaitCondition,
}

impl<T> WaitQueue<T> {
    pub fn new() -> WaitQueue<T> {
        WaitQueue {
            inner: UnsafeCell::new(VecDeque::new()),
            condition: WaitCondition::new()
        }
    }

    pub unsafe fn inner<'a>(&'a self) -> &'a mut VecDeque<T> {
        &mut *self.inner.get()
    }

    pub fn clone(&self) -> WaitQueue<T> where T: Clone {
        WaitQueue {
            inner: UnsafeCell::new(unsafe { self.inner() }.clone()),
            condition: WaitCondition::new()
        }
    }

    pub fn receive(&self) -> T {
        loop {
            if let Some(value) = unsafe { self.inner() }.pop_front() {
                return value;
            }
            self.condition.wait();
        }
    }

    pub fn receive_all(&self) -> VecDeque<T> {
        loop {
            {
                let mut inner = unsafe { self.inner() };
                if ! inner.is_empty() {
                    let mut swap_inner = VecDeque::new();
                    mem::swap(inner.deref_mut(), &mut swap_inner);
                    return swap_inner;
                }
            }
            self.condition.wait();
        }
    }

    pub fn send(&self, value: T) {
        unsafe { self.inner() }.push_back(value);
        self.condition.notify();
    }
}
