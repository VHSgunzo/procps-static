#!/bin/bash
set -e
export MAKEFLAGS="-j$(nproc)"

# WITH_UPX=1

platform="$(uname -s)"
platform_arch="$(uname -m)"

if [ -x "$(which apt 2>/dev/null)" ]
    then
        apt update && apt install -y \
            build-essential clang pkg-config git autoconf libtool libcap-dev \
            libncurses-dev gettext autopoint
fi

if [ -d build ]
    then
        echo "= removing previous build directory"
        rm -rf build
fi

if [ -d release ]
    then
        echo "= removing previous release directory"
        rm -rf release
fi

# create build and release directory
mkdir build
mkdir release
pushd build

# download procps
git clone https://gitlab.com/procps-ng/procps.git
procps_version="$(cd procps && git describe --long --tags|sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g')"
mv procps "procps-${procps_version}"
echo "= downloading procps v${procps_version}"

if [ "$platform" == "Linux" ]
    then
        export CFLAGS="-static"
        export LDFLAGS='--static'
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
fi

echo "= building procps"
pushd procps-${procps_version}
env CFLAGS="$CFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" ./autogen.sh
env CFLAGS="$CFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" ./configure \
    --disable-w --disable-shared LDFLAGS="$LDFLAGS -Wl,--gc-sections"
make DESTDIR="$(pwd)/install" install
popd # procps-${procps_version}

popd # build

shopt -s extglob

echo "= extracting procps binary"
mv build/procps-${procps_version}/install/usr/local/bin/* release 2>/dev/null
mv build/procps-${procps_version}/install/usr/local/sbin/* release 2>/dev/null

echo "= striptease"
for file in release/*
  do
      strip -s -R .comment -R .gnu.version --strip-unneeded "$file" 2>/dev/null
done

if [[ "$WITH_UPX" == 1 && -x "$(which upx 2>/dev/null)" ]]
    then
        echo "= upx compressing"
        for file in release/*
          do
              upx -9 --best "$file" 2>/dev/null
        done
fi

echo "= create release tar.xz"
tar --xz -acf procps-static-v${procps_version}-${platform_arch}.tar.xz release
# cp procps-static-*.tar.xz /root 2>/dev/null

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rf release build
fi

echo "= procps v${procps_version} done"
