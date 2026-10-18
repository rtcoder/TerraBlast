FROM debian:bookworm-slim
RUN useradd --uid 10001 --create-home --home-dir /home/terrablast terrablast
WORKDIR /app
# Build context: repository root, after tools/release.py build --platform server.
COPY --chown=10001:10001 build/server/ /app/
USER 10001:10001
ENV HOME=/home/terrablast
EXPOSE 19170/udp
ENTRYPOINT ["/app/TerraBlast.x86_64", "--headless"]
