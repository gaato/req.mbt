///|
/// The rest of the chain after a step: the later steps and the transport.
pub type Next = async (Request) -> Response raise ReqError

///|
/// A link of the chain around the transport. It may change the request,
/// call `next` (or not, or more than once) and change or replace the result.
/// A client's steps run in array order, the first outermost, the same shape
/// as `@http.Middleware`.
pub type Step = async (Request, Next) -> Response raise ReqError

///|
/// A step that calls `hook` with each request before passing it on.
pub fn on_request(hook : async (Request) -> Unit raise ReqError) -> Step {
  (request, next) => {
    hook(request)
    next(request)
  }
}

///|
/// A step that calls `hook` with each response before returning it.
pub fn on_response(hook : async (Response) -> Unit raise ReqError) -> Step {
  (request, next) => {
    let response = next(request)
    hook(response)
    response
  }
}

///|
/// Runs `request` through `steps`, the first outermost, ending at `last`.
async fn run_steps(
  steps : Array[Step],
  last : Next,
  request : Request,
) -> Response raise ReqError {
  let mut next = last
  for i = steps.length() - 1; i >= 0; i = i - 1 {
    let inner = next
    let step = steps[i]
    next = request => step(request, inner)
  }
  next(request)
}
