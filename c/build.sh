#!/bin/bash
set -e
cc -o listen_tcp -I/opt/homebrew/include -L/opt/homebrew/lib -luv tcp.c
./listen_tcp > log&
SERVER="$!"
echo "test\n" | netcat localhost 10000
sleep 2
kill $SERVER