# Use official Dart image
FROM dart:stable AS build

# Resolve app dependencies
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY quickcab_realtime_server.dart .

# AOT compile the server
RUN dart compile exe quickcab_realtime_server.dart -o server

# Build minimal final image
FROM debian:bookworm-slim
LABEL maintainer="QuickCab"
RUN apt-get update && apt-get install -y libsqlite3-dev sqlite3 ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/server /server
COPY web /web
COPY web_user /web_user

# Render dynamically passes PORT
ENV PORT=8080
EXPOSE $PORT

CMD ["/server"]
