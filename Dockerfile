#
# Build image
#
ARG DEBIAN_IMAGE=debian:stretch-slim
FROM ${DEBIAN_IMAGE} as build
LABEL maintainer="Pavel Volkovitskiy <olfway@olfway.net>"

ENV LANG 'C.UTF-8'
ENV DEBIAN_FRONTEND=noninteractive

COPY --from=olfway/qemu-user-static /qemu-arm-static /usr/bin/
COPY --from=olfway/qemu-user-static /qemu-aarch64-static /usr/bin/

RUN set -x \
    && echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/zz-no-install-recommends

RUN set -x \
    && apt-get update \
    && apt-get dist-upgrade -y \
    && apt-get install -y \
       ca-certificates \
       curl \
       gnupg

WORKDIR /usr/src

ARG SAMBA_VERSION=4.8.2
ARG SAMBA_URL=https://download.samba.org/pub/samba
RUN set -x \
    && curl -O "${SAMBA_URL}/samba-${SAMBA_VERSION}.tar.asc" \
    && curl "${SAMBA_URL}/samba-${SAMBA_VERSION}.tar.gz" | gunzip -d > "samba-${SAMBA_VERSION}.tar"

COPY samba-pubkey.asc .

RUN set -x \
    && gpg --import "samba-pubkey.asc" \
    && echo "52FBC0B86D954B0843324CDC6F33915B6568B7EA:6:" | gpg --import-ownertrust \
    && gpg --verify "samba-${SAMBA_VERSION}.tar.asc" "samba-${SAMBA_VERSION}.tar"

RUN set -x \
    && tar -xf "samba-${SAMBA_VERSION}.tar"

RUN set -x \
    && apt-get update \
    && apt-get install -y \
       build-essential \
       docbook \
       docbook-xml \
       docbook-xsl \
       file \
       libaio-dev \
       libarchive-dev \
       libavahi-client-dev \
       libcap-dev \
       libgcrypt20-dev \
       libgnutls28-dev \
       libgpg-error-dev \
       libgpgme-dev \
       libkrb5-dev \
       libncurses5-dev \
       libpopt-dev \
       pkg-config \
       python \
       xfslibs-dev \
       xsltproc \
       zlib1g-dev

COPY patches patches/

WORKDIR /usr/src/samba-${SAMBA_VERSION}

RUN set -x \
    && patch -i ../patches/samba-4.8.1-hide-pcap-errors.patch -p1

RUN set -x \
    && ./configure \
        --prefix=/app \
        --with-smbpasswd-file=/app/etc/smbpasswd \
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
    && make

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
    && echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/zz-no-install-recommends

RUN set -x \
    && apt-get update \
    && apt-get dist-upgrade -y \
    && apt-get install -y \
       libavahi-client3 \
       libcap2 \
       libgnutls30 \
       libgssapi-krb5-2 \
       libkrb5-3 \
       libpopt0 \
       man-db \
       vim \
    && apt-get clean

COPY --from=build /app/ /app/

COPY scripts/ /app/scripts/

WORKDIR "/app"

ENV PATH=/app/scripts:/app/sbin:/app/bin:/usr/sbin:/usr/bin:/sbin:/bin

CMD [ "/app/scripts/samba-start" ]
