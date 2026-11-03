# The client packager image.
#
# The vendor client is prebuilt, so packaging it needs only the package
# tools and the packager script. The release workflow builds this image
# once and every client matrix job reuses the saved image. The Alpine
# edge snapshot is pinned because its apk-tools 3 creates the same apk
# package schema as the OpenWrt 25.12 SDK.
FROM alpine:edge@sha256:020dfcbaaf4cc1078bf2d9c7ba31a8466e334061dcd2f248001d68f79e52c000

RUN apk add --no-cache curl ca-certificates tar gzip

COPY package-client.sh /usr/local/bin/package-client
RUN chmod 0755 /usr/local/bin/package-client

ENTRYPOINT ["/usr/local/bin/package-client"]
