#!/bin/bash
lake build

function runExample {
    echo "Running $1"
    lake env lean --load-dynlib=build/lib/libLibUV-Basic-1.dylib --run $1 \
      2> >( sed 's/^/  /' ) \
      >  >( sed 's/^/  /' )
}

runExample "examples/counter.lean"