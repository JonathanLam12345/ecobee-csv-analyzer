# Use the official Dart image
FROM dart:stable AS build

# Resolve app dependencies
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

# Copy app source code and compile it
COPY . .
# Ensure bin/server.dart matches the actual name of your server file
RUN dart compile exe bin/server.dart -o bin/server

# Build a minimal runtime image
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/

# Start the server
CMD ["/app/bin/server"]