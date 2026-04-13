# Use official Dart image
FROM dart:stable AS build

# Resolve app dependencies
WORKDIR /app
# Note: we only copy pubspec if we had one and dependencices, but for single-file servers:
COPY quickcab_realtime_server.dart .

# AOT compile the server
RUN dart compile exe quickcab_realtime_server.dart -o server

# Build minimal final image
FROM scratch
LABEL maintainer="QuickCab"
COPY --from=build /runtime/ /
COPY --from=build /app/server /server

# Render dynamically passes PORT
ENV PORT=8080
EXPOSE $PORT

CMD ["/server"]
