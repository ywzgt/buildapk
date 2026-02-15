#!/bin/bash -ex

OUT="$PWD/apkout"
URL="https://github.com/topjohnwu/Magisk"
TAG="$(curl -LIs $URL/releases/latest | grep '^location:' | sed 's/.*\/tag\/\|\r//g')"
JAVA_HOME="$(update-java-alternatives -l | grep 21-jdk | awk '{print$3}')"
if [ ! -d "$JAVA_HOME" ]; then
	echo "Can't find JDK 21"
	exit 1
fi
export JAVA_HOME

if curl -sL "https://api.github.com/repos/$GITHUB_REPOSITORY/releases/tags/${URL##*/}-$TAG" | grep -q 'Not Found'
then
    echo "UP_DIR=$OUT" >> $GITHUB_ENV
    echo "UP_RELEASE=y" >> $GITHUB_ENV
    echo "REL_NAME=${URL##*/}-$TAG" >> $GITHUB_ENV
else
    echo "This release: '${URL##*/}-$TAG' already exists, skip creating it."
    echo "NO_ERROR=y" >> $GITHUB_ENV
    exit 0
fi

git clone --depth 1 -b "$TAG" $URL
cd "${URL##*/}"
git submodule update --init --recursive
./build.py ndk

cat >config.prop<<-EOF
version=$TAG
outdir=$OUT
abiList=arm64-v8a
keyStore=$PWD/../android.jks
keyStorePass=$KS_PASS_RSA
keyAlias=$KEY_ALIAS_RSA
keyPass=$KEY_PASS_RSA
EOF
echo "$ANDROID_KEY_RSA" | base64 -d > ../android.jks

for abi in armeabi-v7a x86 arm64-v8a x86_64 universal; do
	[ "$abi" = "universal" ] && sed -i '/^abiList=/d' config.prop || \
	sed -i "/^abiList=/s/=.*/=$abi/" config.prop
	./build.py -r native
	./build.py -r app
	(cd "$OUT"; mv app-release.apk Magisk-$TAG-$abi.apk)
done
rm -f "$OUT/stub-"*.apk
