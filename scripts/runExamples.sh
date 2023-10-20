#!/bin/bash
lake build

function runExample {
    echo "Running $1"
    lake env lean --load-dynlib=build/lib/libLibUV-Basic-1.dylib $1 | sed 's/^/  /'
}

runExample "examples/counter.lean"