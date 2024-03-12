# syntax=docker/dockerfile:1

FROM ubuntu

RUN apt-get update
RUN apt-get -y install build-essential libtool autotools-dev automake \
    pkg-config bsdmainutils python3 libevent-dev libboost-dev libsqlite3-dev \
    libminiupnpc-dev libnatpmp-dev systemtap-sdt-dev curl git

RUN git clone https://github.com/bitcoin/bitcoin.git
RUN cd bitcoin && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install

RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /bitcoin-dsl

# Install miniscript-cli
COPY miniscript-cli miniscript-cli
RUN cd miniscript-cli && cargo install --path .

# Install RVM, Ruby, and Bundler
RUN apt-get -y install ruby ruby-dev
COPY Gemfile Gemfile
RUN gem install bundler
RUN bundle install

COPY lib lib
COPY spec spec
COPY Rakefile.rb Rakefile.rb
