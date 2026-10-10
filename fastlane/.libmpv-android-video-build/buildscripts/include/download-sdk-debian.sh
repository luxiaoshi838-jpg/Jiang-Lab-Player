#!/bin/bash -e

# . ./include/depinfo.sh

# . ./include/path.sh # load $os var

# [ -z "$TRAVIS" ] && TRAVIS=0 # skip steps not required for CI?
# [ -z "$WGET" ] && WGET=wget # possibility of calling wget differently

# os_ndk="linux"

# echo y | sdkmanager \
# 	"platforms;android-33" \
# 	"build-tools;${v_sdk_build_tools}" \
# 	"ndk;${v_ndk}" \
# 	"cmake;3.22.1"

# echo "checkPoint"
# echo $ANDROID_HOME
