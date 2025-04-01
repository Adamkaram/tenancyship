FROM docker.io/library/rust:1.75 as builder
WORKDIR /usr/src/app
COPY . .
RUN cargo build --release

FROM docker.io/library/debian:bookworm-slim
COPY --from=builder /usr/src/app/target/release/tenant-service /usr/local/bin/
EXPOSE 8080
CMD ["tenant-service"] 