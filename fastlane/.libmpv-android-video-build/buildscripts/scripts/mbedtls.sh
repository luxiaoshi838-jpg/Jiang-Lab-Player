#!/bin/bash -e

. ../../include/depinfo.sh
. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	make clean
	exit 0
else
	exit 255
fi

$0 clean # separate building not supported, always clean

if [ "$ndk_suffix" == "-arm64" ]; then
	make CFLAGS="-fPIC -march=armv8-a+crypto" CXXFLAGS="-fPIC -march=armv8-a+crypto" -j$cores no_test
else
	make CFLAGS="-fPIC" CXXFLAGS="-fPIC" -j$cores no_test
fi

make CFLAGS=-fPIC CXXFLAGS=-fPIC DESTDIR="$prefix_dir" install
