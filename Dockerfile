FROM swift:6.1-jammy

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        pkg-config \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY . .

RUN swift --version

# Build and test
RUN swift build
RUN swift test

CMD ["swift", "test"]
