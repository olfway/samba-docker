#
# Build image
#
ARG DEBIAN_IMAGE=debian:buster-slim
FROM debian:buster-slim as build

ENV LANG 'C.UTF-8'
ENV DEBIAN_FRONTEND=noninteractive

COPY --from=olfway/qemu-user-static /qemu-arm-static /usr/bin/
COPY --from=olfway/qemu-user-static /qemu-aarch64-static /usr/bin/

RUN set -x \
    && echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/zz-force-ipv4 \
    && echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/zz-no-install-recommends

RUN set -x \
    && apt-get update \
    && apt-get install -y \
       ca-certificates \
       curl \
       docbook \
       docbook-xml \
       docbook-xsl \
       file \
       gnupg \
       patch \
       pkg-config \
       python \
       xsltproc

WORKDIR /usr/src

ARG SAMBA_VERSION=4.9.0
ARG SAMBA_URL=https://download.samba.org/pub/samba
RUN set -x \
    && curl --ipv4 -O "${SAMBA_URL}/samba-${SAMBA_VERSION}.tar.asc" \
    && curl --ipv4 "${SAMBA_URL}/samba-${SAMBA_VERSION}.tar.gz" | gunzip -d > "samba-${SAMBA_VERSION}.tar"

COPY samba-pubkey.asc .

RUN set -x \
    && gpg --import "samba-pubkey.asc" \
    && echo "52FBC0B86D954B0843324CDC6F33915B6568B7EA:6:" | gpg --import-ownertrust \
    && gpg --verify "samba-${SAMBA_VERSION}.tar.asc" "samba-${SAMBA_VERSION}.tar"

RUN set -x \
    && tar -xf "samba-${SAMBA_VERSION}.tar"

COPY patches patches/

WORKDIR /usr/src/samba-${SAMBA_VERSION}

RUN set -x \
    && patch -i ../patches/samba-4.8.1-hide-pcap-errors.patch -p1

ARG QEMU
ENV QEMU=$QEMU

ARG TOOLCHAIN
ENV TOOLCHAIN=$TOOLCHAIN

ARG ARCH_DEBIAN
ENV ARCH_DEBIAN=$ARCH_DEBIAN

RUN set -x \
    && if [ "$(dpkg --print-architecture)" = "$ARCH_DEBIAN" ]; then \
          apt-get install -y build-essential ; \
       else \
          apt-get install -y crossbuild-essential-$ARCH_DEBIAN \
          && ln -v -s /usr/bin/$TOOLCHAIN-cpp /usr/$TOOLCHAIN/bin/cpp \
          && ln -v -s /usr/bin/$TOOLCHAIN-gcc /usr/$TOOLCHAIN/bin/gcc \
          && ln -v -s /usr/bin/$TOOLCHAIN-gcc /usr/$TOOLCHAIN/bin/cc \
          && sed -i "s,configure,configure --cross-compile --cross-execute='$QEMU -L /usr/$TOOLCHAIN'," configure ; \
    fi

ENV PATH=/usr/$TOOLCHAIN/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN set -x \
    && dpkg --add-architecture $ARCH_DEBIAN \
    && apt-get update \
    && apt-get install -y \
       libaio-dev:$ARCH_DEBIAN \
       libarchive-dev:$ARCH_DEBIAN \
       libavahi-client-dev:$ARCH_DEBIAN \
       libcap-dev:$ARCH_DEBIAN \
       libcmocka-dev:$ARCH_DEBIAN \
       libgcrypt20-dev:$ARCH_DEBIAN \
       libgnutls28-dev:$ARCH_DEBIAN \
       libgpg-error-dev:$ARCH_DEBIAN \
       libgpgme-dev:$ARCH_DEBIAN \
       libjansson-dev:$ARCH_DEBIAN \
       libkrb5-dev:$ARCH_DEBIAN \
       libncurses5-dev:$ARCH_DEBIAN \
       libpopt-dev:$ARCH_DEBIAN \
       libtdb-dev:$ARCH_DEBIAN \
       xfslibs-dev:$ARCH_DEBIAN \
       zlib1g-dev:$ARCH_DEBIAN

RUN set -x \
        && ./configure \
        --prefix=/app \
        --with-smbpasswd-file=/app/etc/smbpasswd \
        --bundled-libraries=talloc \
        --enable-avahi \
        --disable-iprint \
        --disable-python \
        --with-quotas \
        --with-sendfile-support \
        --with-system-mitkrb5 \
        --without-acl-support \
        --without-winbind \
        --without-ad-dc \
        --without-pam \
        --without-ldap \
        --without-ads

RUN set -x \
    && make install

CMD [ "/bin/bash" ]

#
# Run image
#
FROM ${DEBIAN_IMAGE}
LABEL maintainer="Pavel Volkovitskiy <olfway@olfway.net>"

ENV LANG 'C.UTF-8'
ENV DEBIAN_FRONTEND=noninteractive

COPY --from=olfway/qemu-user-static /qemu-arm-static /usr/bin/
COPY --from=olfway/qemu-user-static /qemu-aarch64-static /usr/bin/

RUN set -x \
    && echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/zz-force-ipv4 \
    && echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/zz-no-install-recommends

RUN set -x \
    && apt-get update \
    && apt-get dist-upgrade -y \
    && apt-get install -y \
       libavahi-client3 \
       libcap2 \
       libgnutls30 \
       libgssapi-krb5-2 \
       libjansson4 \
       libkrb5-3 \
       libpopt0 \
       libtdb1 \
       man-db \
       vim \
    && apt-get clean

COPY --from=build /app/ /app/

COPY scripts/ /app/scripts/

WORKDIR "/app"

ENV PATH=/app/scripts:/app/sbin:/app/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN /app/sbin/smbd --version > /dev/null

CMD [ "/app/scripts/samba-start" ]
