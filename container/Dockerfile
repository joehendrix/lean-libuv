# This is a fairly minimal Ubuntu container that can build
# lean-libuv for testing purposes.
FROM ubuntu:jammy

USER root

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      curl ca-certificates clang-14 expect git libuv1-dev pkg-config && \
    apt-get clean

RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | \
    sh -s -- -y --default-toolchain none

RUN update-alternatives --install /usr/bin/cc cc /usr/bin/clang-14 100

ENV PATH="/root/.elan/bin:${PATH}"

WORKDIR /libuv
