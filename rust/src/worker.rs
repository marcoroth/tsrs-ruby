use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;

use crate::result::{TsrsErrorCode, TsrsResult};

// Type checking recurses deeply; tsrs's CLI uses the same stack size.
const STACK_SIZE: usize = 512 << 20;

type Job = Box<dyn FnOnce() + Send>;

struct Pool {
  sender: Mutex<Sender<Job>>,
}

// tsrs allocates into per-thread arenas that are never freed, so a fresh thread per call would leak one each time.
fn pool() -> &'static Pool {
  static POOL: OnceLock<Pool> = OnceLock::new();

  POOL.get_or_init(|| {
    let (sender, receiver) = channel::<Job>();
    let receiver = Arc::new(Mutex::new(receiver));
    let threads = thread::available_parallelism().map_or(1, |n| n.get()).clamp(1, 4);

    for index in 0..threads {
      let receiver = Arc::clone(&receiver);

      thread::Builder::new()
        .name(format!("tsrs-ruby-{index}"))
        .stack_size(STACK_SIZE)
        .spawn(move || work(&receiver))
        .expect("spawn a tsrs worker thread");
    }

    Pool {
      sender: Mutex::new(sender),
    }
  })
}

fn work(receiver: &Mutex<Receiver<Job>>) {
  loop {
    let job = match receiver.lock() {
      Ok(receiver) => receiver.recv(),
      Err(_) => return,
    };

    match job {
      Ok(job) => job(),
      Err(_) => return,
    }
  }
}

pub fn run<F>(job: F) -> TsrsResult
where
  F: FnOnce() -> TsrsResult + Send + 'static,
{
  let (reply, result) = channel::<TsrsResult>();

  let task: Job = Box::new(move || {
    let outcome = match catch_unwind(AssertUnwindSafe(job)) {
      Ok(result) => result,
      Err(payload) => TsrsResult::error(TsrsErrorCode::Panic, crate::panic_message(&payload)),
    };

    let _ = reply.send(outcome);
  });

  let sent = pool()
    .sender
    .lock()
    .map(|sender| sender.send(task).is_ok())
    .unwrap_or(false);

  if !sent {
    return TsrsResult::error(TsrsErrorCode::Internal, "the tsrs worker threads are gone");
  }

  result
    .recv()
    .unwrap_or_else(|_| TsrsResult::error(TsrsErrorCode::Internal, "a tsrs worker thread stopped without replying"))
}
