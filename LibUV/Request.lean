import LibUV.Stream

namespace UV

inductive Req where
  | connect  : ConnectReq -> Req
  | shutdown : ∀{H : Type}, ShutdownReq H -> Req
  | write    : WriteReq -> Req

end UV
