import LibUV
-- This is example code from:
-- https://medium.com/@padam.singh/an-event-driven-tcp-server-using-libuv-50cce9a473c0

def String.escapeNewLines (s : String) := s.map (fun c => if c == '\n' then ' ' else c)

def UV.TCP.readString (socket : UV.TCP) (eof : UV.IO Unit) (read : String → UV.IO Unit) : UV.IO Unit := do
  socket.read_start fun res => do
    match res with
    | .error e => throw (.errorcode e)
    | .eof => eof
    | .ok bytes =>
      let cmd := String.fromUTF8Unchecked bytes
      read cmd

def UV.TCP.writeString (socket : UV.TCP) (msg : String) (next : UV.IO Unit): UV.IO Unit := do
  let bytes := String.toUTF8 msg
  let _ ← socket.write #[bytes] fun success => do
    if not success then
      throw (.errorcode .EINVAL)
    next

def main : IO Unit := UV.IO.run do
  UV.log "Started loop"
  let loop ← UV.mkLoop
  let addr ← UV.SockAddr.mkIPv4 "127.0.0.1" 10000
  UV.log "Starting listening"
  let server ← loop.mkTCP
  server.bind addr
  server.listen 128 do
    UV.log "Received connection"
    let client ← loop.mkTCP
    server.accept client
    let timer ← loop.mkTimer
    timer.start 10000 20000 do UV.fatal "Timeout"
    let onEOF := do
          UV.log "Client disconnected"
          timer.stop
          client.read_stop
          server.stop
    client.readString onEOF fun msg => do
      UV.log s!"Read '{msg.escapeNewLines}'"
  let client ← loop.mkTCP
  let _ ← client.connect addr $ fun success => do
    match success with
    | .ok => pure ()
    | _ => throw (.errorcode .EINVAL)
    client.writeString "test\n" $ do
      UV.log "Data written"
      --client.stop
  let _stillActive ← loop.run
  UV.log "Finished"
