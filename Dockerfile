# syntax=docker/dockerfile:1

FROM alpine:latest as pythonbuilder
RUN apk add gcc python3 python3-dev musl-dev linux-headers libffi libffi-dev
RUN python -m venv /opt/venv
# Make sure we use the virtualenv:
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install jupyterlab notebook


FROM rust:alpine as rustbuilder
RUN apk --no-cache add build-base gcc
COPY miniscript-cli miniscript-cli
RUN cd miniscript-cli && cargo install --path .


FROM alpine:latest

RUN apk --no-cache add curl ruby ruby-dev python3 bash build-base gcc wget git \
    autoconf automake libtool boost-dev libevent-dev sqlite-dev zeromq-dev linux-headers \
    yaml-dev bitcoin python3-dev \
    pandoc

# # Install bitcoin core from source. This allows us to experiment with various forks.
# RUN git clone --depth 1 --branch v26.0 https://github.com/bitcoin/bitcoin.git
# RUN cd bitcoin && \
#     ./autogen.sh && \
#     ./configure --disable-maintainer-mode --disable-bench --disable-tests --with-gui=no --disable-fuzz-binary --disable-hardening --disable-man && \
#     make -j4 && \
#     make install

WORKDIR /bitcoin-dsl
COPY Gemfile Rakefile.rb .

RUN gem install bundler:2.5.5 && \
    bundle install --without=development && \
    bundle binstubs --all && \
    rm -rf /usr/local/bundle/cache

COPY lib lib
COPY spec spec
COPY notebooks notebooks

COPY --from=rustbuilder /usr/local/cargo/bin/miniscript-cli /usr/local/cargo/bin/miniscript-cli
COPY --from=pythonbuilder /opt/venv /opt/venv

COPY jupyter/kernel.json /root/.local/share/jupyter/kernels/ruby/kernel.json
ENV JUPYTER_PORT=8888 PATH="/opt/venv/bin:/usr/local/cargo/bin:${PATH}"
EXPOSE $JUPYTER_PORT

CMD ["jupyter-lab", "--ip", "0.0.0.0", "--no-browser", "--allow-root", "--notebook-dir", "/bitcoin-dsl/notebooks"]
