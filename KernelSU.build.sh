#!/bin/bash -ex

OUT="$PWD/apkout"
URL="https://github.com/tiann/KernelSU"
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
cd "${URL##*/}/manager"

cat >>gradle.properties<<-EOF
KEYSTORE_FILE=android.jks
KEYSTORE_PASSWORD=$KS_PASS
KEY_ALIAS=$KEY_ALIAS
KEY_PASSWORD=$KEY_PASS
EOF
echo "$ANDROID_KEY" | base64 -d > android.jks

rustup update stable
rustup target add aarch64-unknown-linux-musl
LLVM_BIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="$LLVM_BIN/aarch64-linux-android28-clang"

(cd ../userspace/ksuinit
cargo clean
RUSTFLAGS="-C link-arg=-no-pie" cargo build --target=aarch64-unknown-linux-musl --release
cp target/aarch64-unknown-linux-musl/release/ksuinit ../ksud/bin/aarch64/
cd ../ksud/bin/aarch64/
curl -sL https://api.github.com/repos/tiann/KernelSU/releases/tags/$TAG | \
    sed -n 's/.*browser_download_url.*\(https.*\.ko\)./\1/p' | wget -nv -i -

ls -la
cd ../..
cargo clean
rustup target add x86_64-unknown-linux-musl
CC="$LLVM_BIN/clang" cargo build --target=x86_64-unknown-linux-musl --release
install -Dv target/x86_64-unknown-linux-musl/release/ksud "$OUT/ksud-x86_64-linux-musl")

cargo install cross --git https://github.com/cross-rs/cross --rev 66845c1

for arch in aarch64 x86_64; do
    (cd ..
    cross clean --manifest-path ./userspace/ksud/Cargo.toml
    CROSS_NO_WARNINGS=0 cross build --target $arch-linux-android --release --manifest-path ./userspace/ksud/Cargo.toml
    install -Dv userspace/ksud/target/$arch-linux-android/release/ksud manager/app/src/main/jniLibs/${arch/aarch64/arm64-v8a}/libksud.so)
done

for abi in 64 arm64-v8a x86_64; do
    [ "$abi" = "64" ] || sed -i "/abiFilters += listOf(.*)/s/(.*)/(\"$abi\")/" app/build.gradle.kts
    ./gradlew app:packageRelease
    APK="$(find app/build/outputs/apk/release -name KernelSU_${TAG}_\*-release.apk)"
    f="${APK##*/}"
    mv "$APK" "$OUT/${f%.apk}-$abi.apk"
done
