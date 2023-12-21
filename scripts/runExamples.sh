#!/bin/bash
lake build

search_dir=/the/path/to/base/dir
# Load dylibs for OSX (FIXME: Support Windows and Linux)
dylibs=""
for entry in ".lake/build/lib"/*.dylib;
do
  dylibs+=" --load-dynlib=$entry"
done

function runExample {
    echo "Running $1"
    unbuffer lake env lean $dylibs --run $1
      2> >( sed 's/^/  /' ) \
      >  >( sed 's/^/  /' )
}

if [ $# -eq 0 ]
then
  runExample "examples/counter.lean"
  runExample "examples/phases.lean"
  runExample "examples/tcp.lean"
  runExample "examples/timer.lean"
  runExample "examples/work.lean"
else
  runExample $1
fi

