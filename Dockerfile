# syntax=docker/dockerfile:1

FROM ruby:3.3.0

RUN apt-get update
RUN apt-get install -y  curl \
    python3 \
    python3-dev \
    python3-venv \
    bash \
    libboost-all-dev

# Install bitcoin core from source. This allows us to experiment with various forks.
RUN git clone --depth 1 --branch v26.0 https://github.com/bitcoin/bitcoin.git
RUN cd bitcoin && \
    ./autogen.sh && \
    ./configure --disable-maintainer-mode --disable-bench --disable-tests --with-gui=no --disable-fuzz-binary --disable-hardening --disable-man && \
    make -j4 && \
    make install

WORKDIR /bitcoin-dsl

# Setup rust and rust-miniscript
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install miniscript-cli
COPY miniscript-cli miniscript-cli
RUN cd miniscript-cli && cargo install --path .

# # Install RVM, Ruby, and Bundler
COPY Gemfile Gemfile
RUN gem install bundler

# Install dependencies for gems
RUN bundle install
RUN bundle binstubs --all

# Jupyter notebook setup begin
RUN python3 -m venv venv
RUN . venv/bin/activate
RUN venv/bin/pip install jupyterlab notebook

ENV PATH="/root/.local/bin:${PATH}"

ENV JUPYTER_PORT=8888
EXPOSE $JUPYTER_PORT

# COPY jupyter/start-notebook.py jupyter/start-notebook.sh jupyter/start-singleuser.py jupyter/start-singleuser.sh /usr/local/bin/
# COPY jupyter/jupyter_server_config.py jupyter/docker_healthcheck.py /etc/jupyter/

# HEALTHCHECK --interval=3s --timeout=1s --start-period=3s --retries=3 \
#     CMD /etc/jupyter/docker_healthcheck.py || exit 1
# Jupyter notebook setup end

# iruby setup
RUN git clone -b dsl-binding --depth=1 https://github.com/pool2win/iruby.git
RUN cd iruby && gem build iruby.gemspec && gem install iruby-0.7.4.gem
COPY jupyter/kernel.json /root/.local/share/jupyter/kernels/ruby/kernel.json
# iruby setup end

COPY lib lib
COPY spec spec
COPY notebooks notebooks
COPY Rakefile.rb Rakefile.rb

CMD ["venv/bin/jupyter-lab", "--ip", "0.0.0.0", "--no-browser", "--allow-root", "--notebook-dir", "/bitcoin-dsl/notebooks"]
