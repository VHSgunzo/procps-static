#!/bin/bash
set -e
export MAKEFLAGS="-j$(nproc)"

# WITH_UPX=1
# NO_SYS_MUSL=1

musl_version="latest"

platform="$(uname -s)"
platform_arch="$(uname -m)"

if [ -x "$(which apt 2>/dev/null)" ]
    then
        apt update && apt install -y \
            build-essential clang pkg-config git autoconf libtool libcap-dev \
            libncurses-dev gettext autopoint upx
fi

[ "$musl_version" == "latest" ] && \
  musl_version="$(curl -s https://www.musl-libc.org/releases/|tac|grep -v 'latest'|\
                  grep -om1 'musl-.*\.tar\.gz'|cut -d'>' -f2|sed 's|musl-||g;s|.tar.gz||g')"

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
        echo "= setting CC to musl-gcc"
        if [[ ! -x "$(which musl-gcc 2>/dev/null)" || "$NO_SYS_MUSL" == 1 ]]
            then
                echo "= downloading musl v${musl_version}"
                curl -LO https://www.musl-libc.org/releases/musl-${musl_version}.tar.gz

                echo "= extracting musl"
                tar -xf musl-${musl_version}.tar.gz

                echo "= building musl"
                working_dir="$(pwd)"

                install_dir="${working_dir}/musl-install"

                pushd musl-${musl_version}
                env CFLAGS="$CFLAGS -Os -ffunction-sections -fdata-sections" LDFLAGS='-Wl,--gc-sections' ./configure --prefix="${install_dir}"
                make install
                popd # musl-${musl-version}
                export CC="${working_dir}/musl-install/bin/musl-gcc"
            else
                export CC="$(which musl-gcc 2>/dev/null)"
        fi
        export CFLAGS="-static"
        export LDFLAGS='--static'
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
fi

echo "= building procps"
pushd procps-${procps_version}
env CC="$CC" CFLAGS="$CFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" ./autogen.sh
env CC="$CC" CFLAGS="$CFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" ./configure \
    --disable-w --disable-shared LDFLAGS="$LDFLAGS -Wl,--gc-sections"
for binary in {free,kill,pgrep,pidof,pkill,pmap,pwdx,sysctl,tload,uptime,vmstat,ps/pscommand,pidwait}
    do
        make src/$binary
done
# errors:
# src/slabtop ncurses.h: No such file or directory
# src/watch ncurses.h: No such file or directory
# src/top/top curses.h: No such file or directory
# src/snice
# src/w
# src/skill
#     /usr/bin/ld: /root/procps/musl-install/lib/Scrt1.o: in function `_start_c':
#     Scrt1.c:(.text._start_c+0x1e): undefined reference to `main'

popd # procps-${procps_version}

popd # build

shopt -s extglob

echo "= extracting procps binary"
cp build/procps-${procps_version}/src/!(*.*) release 2>/dev/null
cp build/procps-${procps_version}/src/ps/pscommand release/ps 2>/dev/null

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
tar --xz -acf procps-static-musl-v${procps_version}-${platform_arch}.tar.xz release
# cp procps-static-*.tar.xz /root 2>/dev/null

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rf release build
fi

echo "= procps v${procps_version} done"
