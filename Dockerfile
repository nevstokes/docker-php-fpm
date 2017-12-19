ARG PHP_VERSION=latest
ARG FINAL_BASE_IMAGE=nevstokes/busybox

FROM nevstokes/php-src:${PHP_VERSION} AS src


FROM alpine:3.6 AS build

COPY github-releases.xsl /

COPY --from=src /php.tar.xz .

ENV PHP_INI_DIR=/usr/local/etc/php

RUN apk --update add \
        autoconf \
        ca-certificates \
        file \
        g++ \
        gcc \
        libc-dev \
        make \
        libressl \
        pkgconf \
        re2c \
        xz \
        curl-dev \
        libedit-dev \
        libressl-dev \
        libxml2-dev \
        libxslt-dev \
        postgresql-dev \
    \
    && mkdir -p $PHP_INI_DIR/conf.d \
    && mkdir -p /usr/src/php \
    && tar -Jxf php.tar.xz -C /usr/src/php --strip-components=1

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent
# Enable optimization (-Os — Optimize for size)
# Enable linker optimization
# Adds GNU HASH segments to generated executables
# https://github.com/docker-library/php/issues/272

RUN export CFLAGS="-fstack-protector-strong -fpic -fpie -Os" \
    CPPFLAGS="-fstack-protector-strong -fpic -fpie -Os" \
    LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie" \
    \
    && cd /usr/src/php \
    \
    && ./configure \
        --with-config-file-path="$PHP_INI_DIR" \
        --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
        \
        --disable-cgi \
        \
        --enable-bcmath \
        --enable-calendar \
        --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data \
        --enable-mbstring \
        --enable-opcache \
        \
        --with-curl \
        --with-openssl \
        --with-pdo_pgsql \
        --with-zlib \
        \
        --without-iconv \
        --without-ldap \
        --without-pdo-sqlite \
        --without-pear \
        --without-sqlite3 \
    \
    && for REPO in igbinary/igbinary krakjoe/apcu php-ds/extension phpredis/phpredis \
    ; do \
        export EXT_DIR="ext/`basename ${REPO}`" \
        && mkdir -p ${EXT_DIR} \
        \
        && export TAG=`wget -q https://github.com/${REPO}/releases.atom -O - | xsltproc /github-releases.xsl - | awk -F/ '{ print $NF; }' > versions.$$ && grep -E "^(v|release-)?\`sed -E 's/^(v|release-)//' versions.$$ | grep -E '^[0-9]+(\.[0-9]+){1,2}$' | sort -rg -t. -k1,1 -k2,2 -k3,3 | head -1\`$" versions.$$ && rm versions.$$` \
        && wget -qO- https://github.com/${REPO}/archive/${TAG}.tar.gz | tar xz -C ${EXT_DIR} --strip-components=1; \
    done \
    \
    && rm configure && ./buildconf --force \
    && ./config.nice --enable-apcu --enable-ds --enable-igbinary --enable-redis --enable-redis-igbinary \
    \
    && make -j "$(getconf _NPROCESSORS_ONLN)" \
    && make install \
    && make clean \
    && { find /usr/local/bin /usr/local/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; }

# upstream's php-fpm.conf.default has "include=NONE/etc/php-fpm.d/*.conf"
RUN cd /usr/local/etc \
    && sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null


FROM alpine:3.6 as libs

COPY --from=build /usr/local/sbin/php-fpm /usr/local/sbin/
COPY --from=build /var/cache/apk /var/cache/apk/

# Install the shared libraries required by php-fpm binary and them compress it with upx
RUN echo '@community http://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories \
    && apk --update add upx@community \
    && scanelf --nobanner --needed usr/local/sbin/php-fpm | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' | xargs apk add \
    && upx -9 /usr/local/sbin/php-fpm

# Remove what is no longer needed, which will clean up the shared library directories
RUN apk del --purge alpine-keys apk-tools libc-utils musl-utils scanelf upx

# With the exception of ld-musl, what is actually required is the shared library but named with just the major version
# number, as per its associated symlink. These can then be copied across to the next stage. Copying symlinks across
# effectively hardens them, duplicating the original shared object and inflating image size.
RUN rm /lib/libc.musl-x86_64.so.1 \
    && for lib_dir in $(find / -name lib*.so.* -type f -print | xargs -n 1 dirname | sort -u) \
    ; do \
        find $lib_dir -type l -name lib*.so -maxdepth 1 -print | xargs -rn 1 rm \
        && find $lib_dir -type f -name lib*.so.* -maxdepth 1 -print > libs.$$ \
        && find $lib_dir -type l -name lib*.so.* -maxdepth 1 -exec sh -c 'LINK=$(readlink -f $0) && ln -f $LINK $0' {} \; \
        && cat libs.$$ | xargs rm \
        && find $lib_dir -type l -maxdepth 1 -print | xargs -rn 1 rm; \
    done


FROM ${FINAL_BASE_IMAGE}

ARG BUILD_DATE
ARG VCS_REF
ARG VCS_URL

ENV PHP_INI_DIR=/usr/local/etc/php

# We'll need the php fpm binary...
COPY --from=libs /usr/local/sbin/php-fpm /usr/local/sbin/

# ...and default configuration files
COPY --from=build /usr/local/etc/php-fpm.conf /usr/local/etc/
COPY --from=build /usr/local/etc/php-fpm.d/www.conf.default /usr/local/etc/php-fpm.d/www.conf

# ...along with our custom configuration
COPY conf/zz-docker.conf /usr/local/etc/php-fpm.d/

# As well as all required shared libraries
COPY --from=libs /lib/ld-musl-x86_64.so.1 /lib/libz.so.1 /lib/
COPY --from=libs /usr/lib/*.so.* /usr/lib/
COPY --from=libs /usr/lib/sasl2/*.so.* /usr/lib/sasl2/

USER www-data

ENTRYPOINT ["php-fpm"]
EXPOSE 9000

LABEL maintainer="Nev Stokes <mail@nevstokes.com>" \
      description="PHP FPM" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.schema-version="1.0" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url=$VCS_URL
