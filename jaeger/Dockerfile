ARG ALPINE_VERSION=3.23
FROM alpine:${ALPINE_VERSION} AS go-builder
ARG GO_SOURCE_URL=https://go.dev/dl/go1.27.4.src.tar.gz
RUN apk add --no-cache \
        bash \
        ca-certificates \
        coreutils \
        curl \
        gcc \
        go \
        musl-dev \
        tar
RUN curl --fail --location --output /tmp/go.src.tar.gz "${GO_SOURCE_URL}"
RUN tar --extract --gzip --file /tmp/go.src.tar.gz --directory /tmp
WORKDIR /tmp/go/src
RUN GOROOT_BOOTSTRAP=/usr/lib/go ./make.bash

FROM alpine:${ALPINE_VERSION} AS jaeger-builder
ARG JAEGER_REPOSITORY=https://github.com/jaegertracing/jaeger.git
ARG JAEGER_REVISION=d723f91447f29a345c288f37eb8d1ce7807bc0be
COPY --from=go-builder /tmp/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"
RUN apk add --no-cache \
        bash \
        coreutils \
        curl \
        git \
        gzip \
        jq \
        make \
        nodejs \
        npm \
        python3 \
        tar
WORKDIR /src/jaeger
RUN git clone "${JAEGER_REPOSITORY}" .
RUN git checkout --detach "${JAEGER_REVISION}" && \
    test "$(git rev-parse HEAD)" = "${JAEGER_REVISION}"
RUN git submodule update --init --recursive
RUN go get \
        github.com/andybalholm/brotli@v1.2.7 \
        golang.org/x/crypto@v0.58.1-0.20261009181718-2f1f834330b2 \
        golang.org/x/net@v0.62.0 && \
    go mod tidy
RUN npm install --global corepack && corepack enable
RUN JAEGER_UI_SKIP_RELEASE_CHECK=1 make build-jaeger
RUN mkdir /out && cp cmd/jaeger/jaeger-linux-* /out/jaeger

FROM alpine:${ALPINE_VERSION} AS runtime
ENV JAEGER_LISTEN_HOST=0.0.0.0
RUN apk upgrade --no-cache && \
    apk add --no-cache ca-certificates tzdata && \
    addgroup -S -g 10001 jaeger && \
    adduser -S -D -H -u 10001 -G jaeger jaeger
COPY --from=jaeger-builder /out/jaeger /usr/local/bin/jaeger
COPY config.yaml /etc/jaeger/jaeger.yaml
USER 10001:10001
EXPOSE 4317 4318 13133 16686
ENTRYPOINT ["/usr/local/bin/jaeger"]
CMD ["--config", "/etc/jaeger/jaeger.yaml"]
