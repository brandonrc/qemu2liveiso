#!/bin/bash

check() {
    return 0
}

depends() {
    echo rootfs-block
}

install() {
    inst_hook cmdline 30 "$moddir/live-root.sh"
    inst /sbin/pivot_root
}
