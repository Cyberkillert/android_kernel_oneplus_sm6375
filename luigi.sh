#!/usr/bin/env bash
# luigi.sh — kernel build script for Realme 10 Pro 5G (SM6375 / Snapdragon 695)
# Adapted for Realme 10 Pro 5G / luigi.

set -e

# ---- Device config ----
export CONFIG=vendor/holi-qgki_defconfig
export DEVICE="Realme 10 Pro 5G"
export CODENAME="luigi"
export BUILDER="Cyber"

KDIR=$(pwd)
export KDIR
DATE=$(date +"%Y-%m-%d")
export DATE
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
export COMMIT_HASH

TOOLS="$HOME/essentials"
OUT_DIR="${KDIR}/out"
DIST_DIR="${OUT_DIR}/dist"
AK3="${TOOLS}/AnyKernel3"
PROCS=$(nproc --all)

# ---- Telegram notifications. Set 1 to enable, 0 to disable. ----
export TGI=1
export CHATID="1755220839"
export TOKEN="6661181238:AAE97H1j7w-M-ihF6a3JhWH7qsclyEywOE0"

# ---- Requirements ----
for bin in make curl unzip find dialog; do
	command -v "$bin" >/dev/null || { echo "[✗] Missing required tool: $bin"; exit 1; }
done

# ---- Toolchain: Neutron Clang ----
if [ ! -f "${TOOLS}/neutron-clang/bin/clang" ]; then
	mkdir -p "${TOOLS}/neutron-clang"
	curl -sL -o "${TOOLS}/neutron-clang/antman" \
		"https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman"
	chmod +x "${TOOLS}/neutron-clang/antman"
	(cd "${TOOLS}/neutron-clang" && ./antman -S)
fi

KBUILD_COMPILER_STRING=$("${TOOLS}/neutron-clang/bin/clang" -v 2>&1 | head -n1 | sed 's/(https..*//; s/ version//')
export KBUILD_COMPILER_STRING
export PATH="${TOOLS}/neutron-clang/bin:${PATH}"

# LLVM_IAS=1 forces clang's integrated assembler, avoiding host /usr/bin/as
# mismatches (e.g. "unrecognized option '-EL'").
MAKE=(
	O="${OUT_DIR}"
	ARCH=arm64
	LLVM=1
	LLVM_IAS=1
)

if [ ! -d "${AK3}" ]; then
	git clone --depth=1 https://github.com/Tashar02/AnyKernel3 -b 5.4 "${AK3}"
fi

export KBUILD_BUILD_USER="lucifer"
export KBUILD_BUILD_HOST="Codespaces"

tg() {
	[[ "${TGI}" == "1" && -n "${TOKEN}" && -n "${CHATID}" ]] || return 0
	local response
	response=$(curl -sX POST https://api.telegram.org/bot"${TOKEN}"/sendMessage \
		-d chat_id="${CHATID}" \
		-d parse_mode=Markdown \
		-d disable_web_page_preview=true \
		-d text="$1")
	if ! echo "$response" | grep -q '"ok":true'; then
		local err
		err=$(echo "$response" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')
		echo -e "\n\e[1;31m[✗] tg(): Failed to send message: ${err:-Unknown error}\e[0m" >&2
	fi
}

tgs() {
	[[ "${TGI}" == "1" && -n "${TOKEN}" && -n "${CHATID}" ]] || return 0
	local MD5 response
	MD5=$(md5sum "$1" | cut -d' ' -f1)
	response=$(curl -sX POST -F document=@"$1" https://api.telegram.org/bot"${TOKEN}"/sendDocument \
		-F "chat_id=${CHATID}" \
		-F "parse_mode=Markdown" \
		-F "caption=$2 | *MD5*: \`$MD5\`")
	if ! echo "$response" | grep -q '"ok":true'; then
		local err
		err=$(echo "$response" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')
		echo -e "\n\e[1;31m[✗] tgs(): Failed to send file '$1': ${err:-Unknown error}\e[0m" >&2
	fi
}

abort() {
	if [[ ${TGI} == "1" ]]; then
		if [ -z "${2}" ]; then
			tg "*${1}*"
		else
			tgs "${2}" "*${1}*"
		fi
	fi
	echo -e "\n\e[1;31m[✗] ${1}\e[0m"
	exit 1
}

clean() {
	echo -e "\n\e[1;93m[*] Cleaning...\e[0m"
	rm -rf "${OUT_DIR}"
	rm -rf "${AK3}"/{*.zip,Image,dt*} 2>/dev/null || true
	echo -e "\e[1;32m[✓] Cleaned.\e[0m"
}

rgn() {
	echo -e "\n\e[1;93m[*] Regenerating defconfig...\e[0m"
	make "${MAKE[@]}" "${CONFIG}" || abort "Failed to regenerate defconfig!"
	cp "${OUT_DIR}"/.config "${KDIR}/arch/arm64/configs/${CONFIG}"
}

mcfg() {
	rgn
	make "${MAKE[@]}" menuconfig || abort "menuconfig failed!"
	cp "${OUT_DIR}"/.config "${KDIR}/arch/arm64/configs/${CONFIG}"
}

img() {
	if [[ ${TGI} == "1" ]]; then
		tg "
*Device*: \`${DEVICE} [${CODENAME}]\`
*Date*: \`$(date)\`
*Compiler*: \`${KBUILD_COMPILER_STRING}\`
*Branch*: \`$(git rev-parse --abbrev-ref HEAD 2>/dev/null)\`
*Last Commit*: \`${COMMIT_HASH}\`
"
	fi
	rgn
	echo -e "\n\e[1;93m[*] Building kernel...\e[0m"
	BUILD_START=$(date +%s)
	time make -j"${PROCS}" "${MAKE[@]}" KCFLAGS="-fcolor-diagnostics" 2>&1 | tee log.txt
	BUILD_END=$(date +%s)
	DIFF=$((BUILD_END - BUILD_START))
	if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
		echo -e "\n\e[1;32m[✓] Built in $((DIFF / 60))m $((DIFF % 60))s\e[0m"
		if [[ ${TGI} == "1" ]]; then
			tg "*Kernel built after $((DIFF / 60))m $((DIFF % 60))s!*"
		fi
		mkdir -p "${DIST_DIR}"
		cp -p "${OUT_DIR}"/arch/arm64/boot/{Image,dtbo.img,dtb} "${DIST_DIR}"/
	else
		abort "Kernel build failed!" "${KDIR}/log.txt"
	fi
}

dtb() {
	rgn
	echo -e "\n\e[1;93m[*] Building DTBs...\e[0m"
	make -j"${PROCS}" "${MAKE[@]}" dtbs || abort "DTB build failed!"
	mkdir -p "${DIST_DIR}"
	cp -p "${OUT_DIR}"/arch/arm64/boot/{dtbo.img,dtb} "${DIST_DIR}"/
}

modules() {
	rgn
	echo -e "\n\e[1;93m[*] Building kernel modules...\e[0m"
	make -j"${PROCS}" "${MAKE[@]}" modules || abort "Module build failed!"

	rm -rf "${DIST_DIR}/modules"
	mkdir -p "${DIST_DIR}/modules"

	make "${MAKE[@]}" \
		INSTALL_MOD_PATH="${DIST_DIR}/modules" \
		INSTALL_MOD_STRIP=1 \
		modules_install || abort "Module install failed!"

	KVER=$(find "${DIST_DIR}/modules/lib/modules" \
		-mindepth 1 -maxdepth 1 -type d \
		-printf "%f\n" | head -1)

	[[ -n "${KVER}" ]] || abort "Unable to determine kernel module release!"

	mkdir -p "${DIST_DIR}/modules/vendor/lib/modules"
	cp -a "${DIST_DIR}/modules/lib/modules/${KVER}/." \
		"${DIST_DIR}/modules/vendor/lib/modules/"

	rm -rf "${DIST_DIR}/modules/lib"

	echo -e "\e[1;32m[✓] Modules staged for /vendor/lib/modules/${KVER}\e[0m"
}

mkzip() {
	echo -e "\n\e[1;93m[*] Packaging AnyKernel3 zip...\e[0m"

	[[ -f "${DIST_DIR}/Image" ]] || abort "Image not found! Build kernel first."
	[[ -d "${DIST_DIR}/modules/vendor/lib/modules" ]] || abort "Built modules not found! Build modules first."

	rm -rf "${AK3}/modules"
	mkdir -p "${AK3}/modules"

	cp -p "${DIST_DIR}/Image" "${AK3}/"

	# Use modules built from THIS kernel source, not stock vendor .ko files.
	cp -a "${DIST_DIR}/modules/vendor" "${AK3}/modules/"

	# Keep DTB/DTBO only when generated by the kernel build.
	[[ -f "${DIST_DIR}/dtb" ]] && cp -p "${DIST_DIR}/dtb" "${AK3}/dtb"
	[[ -f "${DIST_DIR}/dtbo.img" ]] && cp -p "${DIST_DIR}/dtbo.img" "${AK3}/dtbo.img"

	(cd "${AK3}" && make zip-"${CODENAME}") || abort "AK3 packaging failed!"

	echo -e "\e[1;32m[✓] Zip built with source-built vendor modules.\e[0m"
}
lto() {
	local flag_e flag_d1 flag_d2
	case "${1}" in
	full) flag_e=LTO_CLANG_FULL; flag_d1=LTO_NONE; flag_d2=LTO_CLANG_THIN ;;
	thin) flag_e=LTO_CLANG_THIN; flag_d1=LTO_NONE; flag_d2=LTO_CLANG_FULL ;;
	none) flag_e=LTO_NONE; flag_d1=LTO_CLANG_FULL; flag_d2=LTO_CLANG_THIN ;;
	*) abort "Use: full | thin | none" ;;
	esac
	"${KDIR}/scripts/config" --file "${KDIR}/arch/arm64/configs/${CONFIG}" \
		-e "${flag_e}" -d "${flag_d1}" -d "${flag_d2}"
	echo -e "\e[1;32m[✓] LTO set to ${1}.\e[0m"
}

upr() {
	"${KDIR}/scripts/config" --file "${KDIR}/arch/arm64/configs/${CONFIG}" \
		--set-str CONFIG_LOCALVERSION "-${1}"
	rgn
	echo -e "\e[1;32m[✓] localversion bumped to -${1}.\e[0m"
}

pause_or_menu() {
	echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
	read -r a1
	[ "${a1}" == "0" ] && exit 0
	clear
	ndialog
}

ndialog() {
	local CHOICE
	CHOICE=$(dialog --clear \
		--backtitle "luigi.sh" \
		--title "Realme 10 Pro 5G Kernel Builder" \
		--menu "Choose an option:" 16 45 30 \
		1 "Build kernel" \
		2 "Build DTBs" \
		3 "Build kernel modules" \
		4 "Build AnyKernel3 zip" \
		5 "Open menuconfig" \
		6 "Regenerate defconfig" \
		7 "Modify LTO mode" \
		8 "Uprev localversion" \
		9 "Clean" \
		10 "Toggle Telegram (currently: ${TGI})" \
		11 "Exit" \
		2>&1 >/dev/tty)
	clear
	case "${CHOICE}" in
	1) img; pause_or_menu ;;
	2) dtb; pause_or_menu ;;
	3) modules; pause_or_menu ;;
	4) mkzip; pause_or_menu ;;
	5) mcfg; pause_or_menu ;;
	5) rgn; pause_or_menu ;;
	6)
		dialog --inputbox --stdout "Enter LTO mode (thin|full|none): " 10 50 >.l
		lt=$(cat .l); rm -f .l
		[ -z "${lt}" ] && abort "No input detected!"
		lto "${lt}"
		pause_or_menu
		;;
	7)
		dialog --inputbox --stdout "Enter version string: " 10 50 >.t
		ver=$(cat .t); rm -f .t
		[ -z "${ver}" ] && abort "No input detected!"
		upr "${ver}"
		pause_or_menu
		;;
	9) clean; pause_or_menu ;;
	10)
		[ "${TGI}" == "1" ] && export TGI=0 || export TGI=1
		ndialog
		;;
	11 | "")
		echo -e "\n\e[1mExiting...\e[0m"
		exit 0
		;;
	esac
}

if [[ -z $* ]]; then
	ndialog
	exit 0
fi
