# syntax=docker/dockerfile:1

FROM alpine:latest

RUN apk update && \
    apk --no-cache add curl ruby ruby-dev python3 bash build-base gcc wget git \
    autoconf automake libtool boost-dev libevent-dev sqlite-dev zeromq-dev linux-headers musl-dev libffi yaml-dev bitcoin python3-dev pipx \
    pandoc

# # Install bitcoin core from source. This allows us to experiment with various forks.
# RUN git clone --depth 1 --branch v26.0 https://github.com/bitcoin/bitcoin.git
# RUN cd bitcoin && \
#     ./autogen.sh && \
#     ./configure --disable-maintainer-mode --disable-bench --disable-tests --with-gui=no --disable-fuzz-binary --disable-hardening --disable-man && \
#     make -j4 && \
#     make install

WORKDIR /bitcoin-dsl

# Setup rust and rust-miniscript
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:/root/.local/bin:${PATH}"

# Install miniscript-cli
COPY miniscript-cli miniscript-cli
RUN cd miniscript-cli && cargo install --path .

# # Install RVM, Ruby, and Bundler
COPY Gemfile Gemfile
RUN gem install bundler:2.5.5 && \
    bundle install && \
    bundle binstubs --all

# Jupyter notebook setup begin
RUN pipx install jupyterlab notebook

ENV JUPYTER_PORT=8888
EXPOSE $JUPYTER_PORT

# iruby setup
RUN git clone -b dsl-binding --depth=1 https://github.com/pool2win/iruby.git
RUN cd iruby && gem build iruby.gemspec && gem install iruby-0.7.4.gem
COPY jupyter/kernel.json /root/.local/share/jupyter/kernels/ruby/kernel.json
# iruby setup end

COPY lib lib
COPY spec spec
COPY notebooks notebooks
COPY Rakefile.rb Rakefile.rb

CMD ["jupyter-lab", "--ip", "0.0.0.0", "--no-browser", "--allow-root", "--notebook-dir", "/bitcoin-dsl/notebooks"]
