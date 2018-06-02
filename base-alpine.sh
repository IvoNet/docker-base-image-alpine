#!/bin/sh

set -e

[ $(id -u) -eq 0 ] || {
	printf >&2 '%s requires root\n' "$0"
	exit 1
}

usage() {
	printf >&2 '%s: [-r release] [-m mirror] [-s] [-c additional repository] [-a arch]\n' "$0"
	exit 1
}

tmp() {
	rm -rf $(pwd)/tmp 2>/dev/null
	TMP=${TMP_DIR}/alpine-docker-${REL}-${ARCH}
	mkdir -p ${TMP}
	ROOTFS=${TMP_DIR}/alpine-docker-rootfs-${REL}-${ARCH}
	mkdir -p ${ROOTFS}
	trap "rm -rf $TMP_DIR" EXIT TERM INT
}

apkv() {
	curl -sSL $MAINREPO/$ARCH/APKINDEX.tar.gz | tar -Oxz |
		grep --text '^P:apk-tools-static$' -A1 | tail -n1 | cut -d: -f2
}

getapk() {
	curl -sSL $MAINREPO/$ARCH/apk-tools-static-$(apkv).apk | tar -xz -C $TMP sbin/apk.static
}

mkbase() {
    chmod 777 $ROOTFS
	docker run --privileged --rm -v ${TMP}:/apkstatic -v ${ROOTFS}:/rootfs alpine:3.7 \
	   /apkstatic/sbin/apk.static \
	   --repository $MAINREPO \
	   --update-cache \
	   --allow-untrusted \
	   --root /rootfs \
	   --initdb add alpine-base
}

conf() {
	printf '%s\n' $MAINREPO > $ROOTFS/etc/apk/repositories
	printf '%s\n' $ADDITIONALREPO >> $ROOTFS/etc/apk/repositories
}

pack() {
	local id
	id=$(tar --numeric-owner -C $ROOTFS -c . | docker import - ivonet/alpine:$REL)

	docker tag $id ivonet/alpine:latest
	docker run -it --rm ivonet/alpine printf 'ivonet/alpine:%s with id=%s created!\n' $REL $id
}

save() {
	[ $SAVE -eq 1 ] || return 0

	tar --numeric-owner -C $ROOTFS -c . | xz > alpine-rootfs-${REL}-${ARCH}.tar.xz
}

while getopts "hr:m:sc:a:" opt; do
	case $opt in
		r)
			REL=$OPTARG
			;;
		m)
			MIRROR=$OPTARG
			;;
		s)
			SAVE=1
			;;
		c)
			ADDITIONALREPO=$OPTARG
			;;
		a)
			ARCH=$OPTARG
			;;
		*)
			usage
			;;
	esac
done

REL=${REL:-edge}
MIRROR=${MIRROR:-http://nl.alpinelinux.org/alpine}
SAVE=${SAVE:-0}
MAINREPO=$MIRROR/$REL/main
ADDITIONALREPO=$MIRROR/$REL/${ADDITIONALREPO:-community}
ARCH=${ARCH:-$(uname -m)}
TMP_DIR=$(pwd)/tmp/

tmp
getapk
mkbase
conf
pack
save

