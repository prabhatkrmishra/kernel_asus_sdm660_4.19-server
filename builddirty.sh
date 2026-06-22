echo ''
echo '======================================================'
echo Starting kernel build.
echo '======================================================'

TOP=$(realpath .)

# export aosp gcc toolchains path
export PATH="$TOP/tools/clang/host/linux-x86/clang-r416183b/bin:$PATH"
export LD_LIBRARY_PATH="$TOP/tools/clang/host/linux-x86/clang-r416183b/lib64:$LD_LIBRARY_PATH"
export PATH="$TOP/tools/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin:$PATH"
export PATH="$TOP/tools/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin:$PATH"

# export required kernel flags
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-android-
export CROSS_COMPILE_ARM32=arm-linux-androideabi-

cd msm-4.19

# clean kernel source and out directory

echo ''
echo "[ IMAGE OUTPUT ]: $TOP/out"
echo "[ BUILD OUTPUT ]: $TOP/out/msm-4.19"
echo ''

OUT="$TOP/out/msm-4.19"

# start make builds
make O="$OUT" CC=clang AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump READELF=llvm-readelf OBJSIZE=llvm-size STRIP=llvm-strip HOSTCC=clang HOSTCXX=clang++ olddefconfig

time make O="$OUT" CC=clang AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump READELF=llvm-readelf OBJSIZE=llvm-size STRIP=llvm-strip HOSTCC=clang HOSTCXX=clang++ --jobs=13

cd ../

# Zipping kernel build
FILE="$TOP/out/msm-4.19/arch/arm64/boot/Image.gz-dtb"
echo "$FILE"
if [[ -f "$FILE" ]]
   then
   echo '======================================================'
   echo 'Kernel Build Successful !'
   echo '======================================================'
   echo ''
   cp "$TOP/out/msm-4.19/arch/arm64/boot/Image" "$TOP/out"
   cp "$TOP/out/msm-4.19/arch/arm64/boot/Image.gz" "$TOP/out"
   cp "$TOP/out/msm-4.19/arch/arm64/boot/Image.gz-dtb" "$TOP/out"
   cp "$TOP/out/msm-4.19/arch/arm64/boot/dts/vendor/qcom/sdm636-qrd-X00TD.dtb" "$TOP/out"
   echo '======================================================'
   echo "Kernel images and dtb present in $TOP/out"
   echo '======================================================'
else
echo ''
echo 'Kernel build Unsuccessfull !!!!'
echo ''
fi
