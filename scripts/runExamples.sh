#!/bin/bash
lake build

search_dir=/the/path/to/base/dir
if [[ "$OSTYPE" == "darwin"* ]]; then
  dsoext=.dylib
else
  dsoext=.so
fi


dynlibs=""
for entry in ".lake/build/lib"/*$dsoext
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
else
  runExample $1
fi

