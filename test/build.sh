#!/bin/sh
set -e

LIBUV_VER=1.47.0
LIBUV_DIR="libuv-${LIBUV_VER}"
LIBUV_BUILD="$PWD/build"

if [ ! -d "$LIBUV_DIR" ]; then
  curl -s -f https://dist.libuv.org/dist/v${LIBUV_VER}/libuv-v${LIBUV_VER}-dist.tar.gz | tar xz
fi

cd $LIBUV_DIR
if [ ! -f Makefile ]; then
    CFLAGS=-fPIC ./configure --prefix=$LIBUV_BUILD
fi
make
make install
cd ..