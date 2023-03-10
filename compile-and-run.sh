#!/bin/bash -e
# SPDX-License-Identifier: MIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [ -z "${ADECLANGFORMAT_WORKFLOW+x}" ]; then
	echo ADECLANGFORMAT_WORKFLOW not defined, defaulting to \"default\"
	ADECLANGFORMAT_WORKFLOW=default
fi
if [ -z "${PRJ1_WORKFLOW+x}" ]; then
	echo PRJ1_WORKFLOW not defined, defaulting to \"shared\"
	PRJ1_WORKFLOW=shared
fi
if [ -z "${PRJ2_WORKFLOW+x}" ]; then
	echo PRJ2_WORKFLOW not defined, defaulting to \"shared\"
	PRJ2_WORKFLOW=shared
fi

big_message() {
	echo
	echo "--------"
	echo "$@"
	echo "--------"
	echo
}

set_system_info() {
    # BASED ON https://unix.stackexchange.com/questions/6345/how-can-i-get-distribution-name-and-version-number-in-a-simple-shell-script
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=GNU/Linux
        DISTRO="${NAME}"
        VER="${VERSION_ID}"
    elif type lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        OS=GNU/Linux
        DISTRO="$(lsb_release -si)"
        VER="$(lsb_release -sr)"
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        OS=GNU/Linux
        DISTRO=$DISTRIB_ID
        VER="${DISTRIB_RELEASE}"
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        OS=GNU/Linux
        DISTRO=Debian
        VER="$(cat /etc/debian_version)"
    elif [ -f /etc/SuSe-release ] || [ -f /etc/redhat-release ]; then
        # Older Red Hat, CentOS, etc.
        OS=GNU/Linux
        DISTRO="$(grep -oP '^\w+' /etc/redhat-release)"
        VER="$(grep -oP '\d+(\.\d+)*' /etc/redhat-release)"
    elif [ "$(uname -s)" == Darwin ]; then
        # Not sure whether the test for watchOS, tvOS etc is different.

        # MacOS doesn't seem to have uname -o
        OS=Darwin
        DISTRO="$(uname -s)"
        VER="(uname -r)"
    else
        # Fall back to uname, e.g. "Linux <version>",
        # also works for BSD, Cygwin, MINGW, etc.
        OS="$(uname -o)"
        DISTRO="$(uname -s)"
        VER="$(uname -r)"
		if [ "$OS" == "" ] || [ "$DISTRO" == "" ] || [ "$VER" == "" ]; then
			echo "One or more 'uname' command(s) failed." >&2
			exit 1
		fi
    fi
}

set_cmake() {
	if [ ! -z "${CMAKE_DIR}" ]; then
		export CMAKE_CMD="${CMAKE_DIR}/bin/cmake"
	else
		export CMAKE_CMD="$(which cmake)"
	fi
	echo CMAKE_CMD: "$CMAKE_CMD"
}

# The CMakePresets.json files check the CMake version, however cmake itself
# does not support the presets file until CMake 3.19.
check_cmake_version() {
	local min_major=3
	local min_minor=19

	local version_string="$("${CMAKE_CMD}" --version | grep -oP '(?<=^cmake version ).*')"
	local major_number="$(echo "${version_string}" | grep -oP '^\d+(?=[\.$])')"
	local minor_number="$(echo "${version_string}" | grep -oP '(?<=^'"${major_number}"'\.)\d+(?=[\.$])')"
	if [ "${major_number}" -gt "${min_major}" ] || [ "${major_number}" -eq "${min_major}" ] && [ "${minor_number}" -ge "${min_minor}" ]; then
		echo "OK, CMake version is ${version_string} >= ${min_major}.${min_minor}."
	else
		echo "ERROR, CMake version is ${version_string} which is less than the minimum required of ${min_major}.${min_minor}." >&2
		exit 1
	fi
}

check_vcpkg() {
	if [ "${VCPKG_DIR+x}" == "" ]; then
		export VCPKG_DIR="${SCRIPT_DIR}/vcpkg"
		echo "VCPKG_DIR not set; setting it to $VCPKG_DIR ." >&2
	fi

	export VCPKG_EXE="$VCPKG_DIR/vcpkg"
	big_message "Assuming vcpkg executable is \"$VCPKG_EXE\" and running vcpkg bootstrap."
	if [ "$OS" == GNU/Linux ] || [ "$OS" == Darwin ]; then
		local vcpkg_bootstrap="$VCPKG_DIR/bootstrap-vcpkg.sh"
		"${vcpkg_bootstrap}"
	elif [ "$OS" == Msys ]; then
		local vcpkg_bootstrap="$VCPKG_DIR/bootstrap-vcpkg.bat"
		# 'cmd /c <cmd>' but since we're on an Msys shell, we need to add an
		# extra '/' to '/c' so that the shell understands we aren't passing a
		# file path that needs to be transformed into backslashes.
		cmd //c "${vcpkg_bootstrap}"
	else
		echo "Unexpected platform \"$OS\"." >&2
		exit 1
	fi

	if ! "${VCPKG_EXE}" version; then
		echo "vcpkg executable does not exist or does not work." >&2
		exit 1
	fi
}

set_system_info

set_cmake
big_message "Assuming cmake command is \"${CMAKE_CMD}\""
check_cmake_version

big_message "Checking vcpkg"
check_vcpkg
# Nothing to do to install vcpkg packages; the packages will be installed
# as part of the CMake build (as part of running the vcpkg toolchain file most
# likely).

cd "${SCRIPT_DIR}"
if [ ! -d vcpkg ]; then
	# Do not run the git command here: it is frequent to produce tarballs of
	# a repo's sources and then distribute the tarball. If we use a 'git'
	# command here, source tarballs would not work because the extracted
	# tarball is not a Git repo.
	echo "vcpkg/ dir does not exist; did you clone this repos's submodules?" >&2
	echo "Run: git submodule update --init --recursive" >&2
	exit 1
fi
rm -rf {AdeClangFormat,prj1,prj2}/{build,vcpkg_installed} install

big_message "AdeClangFormat workflow ${ADECLANGFORMAT_WORKFLOW}"
cd "${SCRIPT_DIR}"/AdeClangFormat
"${CMAKE_CMD}" --workflow --preset "${ADECLANGFORMAT_WORKFLOW}"
"${CMAKE_CMD}" --install build --config "${CMAKE_CONFIG_TYPE}"
big_message "prj1 workflow ${PRJ1_WORKFLOW}"
cd "${SCRIPT_DIR}"/prj1
"${CMAKE_CMD}" --workflow --preset "${PRJ1_WORKFLOW}"
"${CMAKE_CMD}" --install build --config "${CMAKE_CONFIG_TYPE}"
big_message "prj2 workflow ${PRJ2_WORKFLOW}"
cd "${SCRIPT_DIR}"/prj2
"${CMAKE_CMD}" --workflow --preset "${PRJ2_WORKFLOW}"
"${CMAKE_CMD}" --install build --config "${CMAKE_CONFIG_TYPE}"
big_message "Running executable"
cd "${SCRIPT_DIR}"
./install/bin/exe

