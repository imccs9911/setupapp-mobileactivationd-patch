#!/usr/bin/env bash

mkdir -p logs
verbose=1

{

echo "[*] Command ran:`if [ $EUID = 0 ]; then echo " sudo"; fi` ./palera1n.sh $@"

# =========
# Variables
# =========
ipsw="" # IF YOU WERE TOLD TO PUT A CUSTOM IPSW URL, PUT IT HERE. YOU CAN FIND THEM ON https://appledb.dev
version="1.4.0-High Sierra"
os=$(uname)
dir="$(pwd)/binaries/$os"
commit=$(git rev-parse --short HEAD)
branch=$(git rev-parse --abbrev-ref HEAD)
max_args=1
arg_count=0
disk=8
fs=disk0s1s$disk

# =========
# Functions
# =========
remote_cmd() {
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "$@"
}

remote_cp() {
    "$dir"/sshpass -p 'alpine' scp -o StrictHostKeyChecking=no -P2222 $@
}

step() {
    for i in $(seq "$1" -1 1); do
        printf '\r\e[1;36m%s (%d) ' "$2" "$i"
        sleep 1
    done
    printf '\r\e[0m%s (0)\n' "$2"
}

print_help() {
    cat << EOF
Usage: $0 [Options] [ subcommand | iOS version ]
iOS 15.0-16.2 jailbreak tool for checkm8 devices

Options:
    --help              Print this help
    --tweaks            Enable tweaks
    --semi-tethered     When used with --tweaks, make the jailbreak semi-tethered instead of tethered
    --dfuhelper         A helper to help get A11 devices into DFU mode from recovery mode
    --skip-fakefs       Don't create the fakefs even if --semi-tethered is specified
    --no-baseband       Indicate that the device does not have a baseband
    --restorerootfs     Remove the jailbreak (Actually more than restore rootfs)
    --debug             Debug the script
    --serial            Enable serial output on the device (only needed for testing with a serial cable)

Subcommands:
    dfuhelper           An alias for --dfuhelper
    clean               Deletes the created boot files

The iOS version argument should be the iOS version of your device.
It is required when starting from DFU mode.
EOF
}

parse_opt() {
    case "$1" in
        --)
            no_more_opts=1
            ;;
        --tweaks)
            tweaks=1
            semi_tethered=1
            ;;
        --semi-tethered)
            semi_tethered=1
            ;;
        --dfuhelper)
            dfuhelper=1
            ;;
        --skip-fakefs)
            skip_fakefs=1
            ;;
        --no-baseband)
            no_baseband=1
            ;;
        --serial)
            serial=1
            ;;
        --dfu)
            echo "[!] DFU mode devices are now automatically detected and --dfu is deprecated"
            ;;
        --restorerootfs)
            restorerootfs=1
            ;;
        --debug)
            debug=1
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            echo "[-] Unknown option $1. Use $0 --help for help."
            exit 1;
    esac
}

parse_arg() {
    arg_count=$((arg_count + 1))
    case "$1" in
        dfuhelper)
            dfuhelper=1
            ;;
        clean)
            clean=1
            ;;
        *)
            version="$1"
            ;;
    esac
}

parse_cmdline() {
    for arg in $@; do
        if [[ "$arg" == --* ]] && [ -z "$no_more_opts" ]; then
            parse_opt "$arg";
        elif [ "$arg_count" -lt "$max_args" ]; then
            parse_arg "$arg";
        else
            echo "[-] Too many arguments. Use $0 --help for help.";
            exit 1;
        fi
    done
}

recovery_fix_auto_boot() {
    if [ "$1" = "--tweaks" ]; then
        "$dir"/irecovery -c "setenv auto-boot false"
        "$dir"/irecovery -c "saveenv"
    else
        "$dir"/irecovery -c "setenv auto-boot true"
        "$dir"/irecovery -c "saveenv"
    fi

    if [[ "$@" == *"--semi-tethered"* ]]; then
        "$dir"/irecovery -c "setenv auto-boot true"
        "$dir"/irecovery -c "saveenv"
    fi
}

_info() {
    if [ "$1" = 'recovery' ]; then
        echo $("$dir"/irecovery -q | grep "$2" | sed "s/$2: //")
    elif [ "$1" = 'normal' ]; then
        echo $("$dir"/ideviceinfo | grep "$2: " | sed "s/$2: //")
    fi
}

_pwn() {
    pwnd=$(_info recovery PWND)
    if [ "$pwnd" = "" ]; then
        echo "[*] Pwning device"
        "$dir"/gaster pwn
        sleep 2
        #"$dir"/gaster reset
        #sleep 1
    fi
}

_reset() {
    echo "[*] Resetting DFU state"
    "$dir"/gaster reset
}

get_device_mode() {
    if [ "$os" = "Darwin" ]; then
        apples="$(system_profiler SPUSBDataType 2> /dev/null | grep -B1 'Vendor ID: 0x05ac' | grep 'Product ID:' | cut -dx -f2 | cut -d' ' -f1 | tail -r)"
    elif [ "$os" = "Linux" ]; then
        apples="$(lsusb | cut -d' ' -f6 | grep '05ac:' | cut -d: -f2)"
    fi
    local device_count=0
    local usbserials=""
    for apple in $apples; do
        case "$apple" in
            12a8|12aa|12ab)
            device_mode=normal
            device_count=$((device_count+1))
            ;;
            1281)
            device_mode=recovery
            device_count=$((device_count+1))
            ;;
            1227)
            device_mode=dfu
            device_count=$((device_count+1))
            ;;
            1222)
            device_mode=diag
            device_count=$((device_count+1))
            ;;
            1338)
            device_mode=checkra1n_stage2
            device_count=$((device_count+1))
            ;;
            4141)
            device_mode=pongo
            device_count=$((device_count+1))
            ;;
        esac
    done
    if [ "$device_count" = "0" ]; then
        device_mode=none
    elif [ "$device_count" -ge "2" ]; then
        echo "[-] Please attach only one device" > /dev/tty
        kill -30 0
        exit 1;
    fi
    if [ "$os" = "Linux" ]; then
        usbserials=$(cat /sys/bus/usb/devices/*/serial)
    elif [ "$os" = "Darwin" ]; then
        usbserials=$(system_profiler SPUSBDataType 2> /dev/null | grep 'Serial Number' | cut -d: -f2- | sed 's/ //')
    fi
    if grep -qE '(ramdisk tool|SSHRD_Script) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{1,2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}' <<< "$usbserials"; then
        device_mode=ramdisk
    fi
    echo "$device_mode"
}

_wait() {
    if [ "$(get_device_mode)" != "$1" ]; then
        echo "[*] Waiting for device in $1 mode"
    fi

    while [ "$(get_device_mode)" != "$1" ]; do
        sleep 1
    done

    if [ "$1" = 'recovery' ]; then
        recovery_fix_auto_boot;
    fi
}

_dfuhelper() {
    local step_one;
    deviceid=$( [ -z "$deviceid" ] && _info normal ProductType || echo $deviceid )
    step_one="Hold volume down + side button"
    echo "[*] Press any key when ready for DFU mode"
    read -n 1 -s
    step 3 "Get ready"
    step 4 "$step_one" &
    sleep 3
    "$dir"/irecovery -c "reset"
    step 1 "Keep holding"
    step 10 'Release side button, but keep holding volume down'
    sleep 1
    
    if [ "$(get_device_mode)" = "dfu" ]; then
        echo "[*] Device entered DFU!"
    else
        echo "[-] Device did not enter DFU mode, rerun the script and try again"
        return -1
    fi
}

_kill_if_running() {
    if (pgrep -u root -xf "$1" &> /dev/null > /dev/null); then
        # yes, it's running as root. kill it
        sudo killall $1
    else
        if (pgrep -x "$1" &> /dev/null > /dev/null); then
            killall $1
        fi
    fi
}

_exit_handler() {
    [ $? -eq 0 ] && exit
    echo "[-] An error occurred"

    if [ -d "logs" ]; then
        cd logs
        for file in *.log; do
            if [[ "$file" != "SUCCESS_"* ]] && [[ "$file" != "FAIL_"* ]]; then
                mv "$file" FAIL_${file}
            fi
        done
        cd ..
    fi

    echo "[*] A failure log has been made. If you're going ask for help, please attach the latest log."
}
trap _exit_handler EXIT

# ===========
# Fixes
# ===========

# ============
# Dependencies
# ============

# Check for required commands
if [ "$os" = 'Linux' ]; then
    linux_cmds='lsusb'
fi

for cmd in curl unzip python3 git ssh scp killall sudo grep pgrep ${linux_cmds}; do
    if ! command -v "${cmd}" > /dev/null; then
        if [ "$cmd" = "python3" ]; then
            echo "[-] Command '${cmd}' not installed, please install it!";
            if [ "$os" = 'Darwin' ]; then
                if [ ! -e python-3.7.6-macosx10.6.pkg ]; then
                    curl -k https://www.python.org/ftp/python/3.7.6/python-3.7.6-macosx10.6.pkg -o python-3.7.6-macosx10.6.pkg
                fi
                open -W python-3.7.6-macosx10.6.pkg
            fi
            if ! command -v "${cmd}" > /dev/null; then
                cmd_not_found=1
            fi
        else
            if ! command -v "${cmd}" > /dev/null; then
                echo "[-] Command '${cmd}' not installed, please install it!";
                cmd_not_found=1
            fi
        fi
    fi
done
if [ "$cmd_not_found" = "1" ]; then
    exit 1
fi

# Download gaster
if [ -e "$dir"/gaster ]; then
    "$dir"/gaster &> /dev/null > /dev/null | grep -q 'usb_timeout: 5' && rm "$dir"/gaster
fi

if [ ! -e "$dir"/gaster ]; then
    curl -k -sLO https://nightly.link/palera1n/gaster/workflows/makefile/main/gaster-"$os".zip
    unzip gaster-"$os".zip
    mv gaster "$dir"/
    rm -rf gaster gaster-"$os".zip
fi

# Check for pyimg4
if ! python3 -c 'import pkgutil; exit(not pkgutil.find_loader("pyimg4"))'; then
    python3 -m pip install pyimg4
fi

# ============
# Prep
# ============

# Update submodules
git submodule update --init --recursive

# Re-create work dir if it exists, else, make it
if [ -e work ]; then
    rm -rf work
    mkdir work
else
    mkdir work
fi

chmod +x "$dir"/*
#if [ "$os" = 'Darwin' ]; then
#    xattr -d com.apple.quarantine "$dir"/*
#fi

# ============
# Start
# ============

echo "palera1n | Version $version-$branch-$commit"
echo "Written by Nebula and Mineek | Some code and ramdisk from Nathan"
echo ""

version=""
parse_cmdline "$@"

if [ "$debug" = "1" ]; then
    set -o xtrace
fi

if [ "$clean" = "1" ]; then
    sudo rm -rf boot* work .tweaksinstalled
    sudo rm -rf blobs
    sudo rm -rf sshramdisk/ramdisk
    echo "[*] Removed the created boot files"
    exit
fi

if [ -z "$tweaks" ] && [ "$semi_tethered" = "1" ]; then
    echo "[!] --semi-tethered may not be used with rootless"
    echo "    Rootless is already semi-tethered"
    >&2 echo "Hint: to use tweaks on semi-tethered, specify the --tweaks option"
    exit 1;
fi

if [ "$tweaks" = 1 ] && [ ! -e ".tweaksinstalled" ] && [ ! -e ".disclaimeragree" ] && [ -z "$semi_tethered" ] && [ -z "$restorerootfs" ]; then
    echo "!!! WARNING WARNING WARNING !!!"
    echo "This flag will add tweak support BUT WILL BE TETHERED."
    echo "THIS ALSO MEANS THAT YOU'LL NEED A PC EVERY TIME TO BOOT."
    echo "THIS WORKS ON 15.0-16.2"
    echo "DO NOT GET ANGRY AT US IF YOUR DEVICE IS BORKED, IT'S YOUR OWN FAULT AND WE WARNED YOU"
    echo "DO YOU UNDERSTAND? TYPE 'Yes, do as I say' TO CONTINUE"
    read -r answer
    if [ "$answer" = 'Yes, do as I say' ]; then
        echo "Are you REALLY sure? WE WARNED YOU!"
        echo "Type 'Yes, I am sure' to continue"
        read -r answer
        if [ "$answer" = 'Yes, I am sure' ]; then
            echo "[*] Enabling tweaks"
            tweaks=1
            touch .disclaimeragree
        else
            echo "[-] Please type it exactly if you'd like to proceed. Otherwise, remove --tweaks, or add --semi-tethered"
            exit
        fi
    else
        echo "[-] Please type it exactly if you'd like to proceed. Otherwise, remove --tweaks, or add --semi-tethered"
        exit
    fi
fi

# Get device's iOS version from ideviceinfo if in normal mode
echo "[*] Waiting for devices"
while [ "$(get_device_mode)" = "none" ]; do
    sleep 1;
done
echo $(echo "[*] Detected $(get_device_mode) mode device" | sed 's/dfu/DFU/')

if grep -E 'pongo|checkra1n_stage2|diag' <<< "$(get_device_mode)"; then
    echo "[-] Detected device in unsupported mode '$(get_device_mode)'"
    exit 1;
fi

if [ "$(get_device_mode)" != "normal" ] && [ -z "$version" ] && [ "$dfuhelper" != "1" ]; then
    echo "[-] You must pass the version your device is on when not starting from normal mode"
    exit
fi

if [ "$(get_device_mode)" = "ramdisk" ]; then
    # If a device is in ramdisk mode, perhaps iproxy is still running?
    _kill_if_running iproxy
    echo "[*] Rebooting device in SSH Ramdisk"
    if [ "$os" = 'Linux' ]; then
        sudo "$dir"/iproxy 2222 22 &
    else
        "$dir"/iproxy 2222 22 &
    fi
    sleep 2
    remote_cmd "/usr/sbin/nvram auto-boot=false"
    remote_cmd "/sbin/reboot"
    _kill_if_running iproxy
    _wait recovery
fi

if [ "$(get_device_mode)" = "normal" ]; then
    version=${version:-$(_info normal ProductVersion)}
    arch=$(_info normal CPUArchitecture)
    if [ "$arch" = "arm64e" ]; then
        echo "[-] palera1n doesn't, and never will, work on non-checkm8 devices"
        exit
    fi
    echo "Hello, $(_info normal ProductType) on $version!"

    echo "[*] Switching device into recovery mode..."
    "$dir"/ideviceenterrecovery $(_info normal UniqueDeviceID)
    _wait recovery
fi

# Grab more info
echo "[*] Getting device info..."
cpid=$(_info recovery CPID)
model=$(_info recovery MODEL)
deviceid=$(_info recovery PRODUCT)

if [ "$dfuhelper" = "1" ]; then
    echo "[*] Running DFU helper"
    _dfuhelper "$cpid"
    exit
fi

sshrd19G69="0"

if [ ! "$ipsw" = "" ]; then
    ipswurl=$ipsw
else
    if [ "$version" = "15.6" ]; then
        echo "!!! WARNING WARNING WARNING !!!"
        echo "This version you have set is 15.6, which is the STABLE RELEASE of iOS 15.6."
        echo "THIS MEANS THAT IF UR DEVICE IS RUNNING 15.6 RC 1, IT WILL NOT BOOT"
        echo "You have two options, you can proceed with 15.6, or you can change it to 19G69."
        echo "IF YOU ARE RUNNING IOS 15.6 RC 1 19G69 TYPE 'Yes'"
        read -r answer
        if [ "$answer" = 'Yes' ]; then
            echo "Are you REALLY sure? WE WARNED YOU!"
            echo "Type 'Yes, I am sure' to continue"
            read -r answer
            if [ "$answer" = 'Yes, I am sure' ]; then
                echo "[*] Enabling 19G69"
                ipswurl=$(curl -k -sL "https://api.appledb.dev/ios/iOS;19G69.json" | "$dir"/jq -r .devices\[\"$deviceid\"\].ipsw)
                sshrd19G69="1"
            else
                ipswurl=$(curl -k -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$dir"/jq '.firmwares | .[] | select(.version=="'"$version"'") | .url' --raw-output)
            fi
        fi
        ipswurl=$(curl -k -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$dir"/jq '.firmwares | .[] | select(.version=="'"$version"'") | .url' --raw-output)
    else
        if [ "$version" = "19G69" ]; then
            ipswurl=$(curl -k -sL "https://api.appledb.dev/ios/iOS;19G69.json" | "$dir"/jq -r .devices\[\"$deviceid\"\].ipsw)
            sshrd19G69="1"
        else
            ipswurl=$(curl -k -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$dir"/jq '.firmwares | .[] | select(.version=="'"$version"'") | .url' --raw-output)
        fi
    fi
fi

if [ "$restorerootfs" = "1" ]; then
    sudo rm -rf "blobs/"$deviceid"-"$version".shsh2" "boot-$deviceid" work .tweaksinstalled
    sudo rm -rf ramdisk/sshramdisk
fi

# Have the user put the device into DFU
if [ "$(get_device_mode)" != "dfu" ]; then
    recovery_fix_auto_boot;
    _dfuhelper "$cpid" || {
        echo "[-] failed to enter DFU mode, run palera1n.sh again"
        exit -1
    }
fi
sleep 2

# ============
# Ramdisk
# ============

# Dump blobs, and install pogo if needed 
if [ -f blobs/"$deviceid"-"$version".der ]; then
    if [ -f .rd_in_progress ]; then
        rm blobs/"$deviceid"-"$version".der
    fi
fi

if [ ! -f blobs/"$deviceid"-"$version".der ]; then
    mkdir -p blobs
    _kill_if_running iproxy

    cd ramdisk
    chmod +x sshrd.sh
    echo "[*] Creating ramdisk"
    if [ "$sshrd19G69" = "1" ]; then
        ./sshrd.sh 19G69 `if [ -z "$tweaks" ]; then echo "rootless"; fi`
    else
        ./sshrd.sh "$version" `if [ -z "$tweaks" ]; then echo "rootless"; fi`
    fi

    echo "[*] Booting ramdisk"
    ./sshrd.sh boot
    cd ..
    # remove special lines from known_hosts
    if [ -f ~/.ssh/known_hosts ]; then
        if [ "$os" = "Darwin" ]; then
            sed -i.bak '/localhost/d' ~/.ssh/known_hosts
            sed -i.bak '/127\.0\.0\.1/d' ~/.ssh/known_hosts
        elif [ "$os" = "Linux" ]; then
            sed -i '/localhost/d' ~/.ssh/known_hosts
            sed -i '/127\.0\.0\.1/d' ~/.ssh/known_hosts
        fi
    fi

    # Execute the commands once the rd is booted
    if [ "$os" = 'Linux' ]; then
        sudo "$dir"/iproxy 2222 22 &
    else
        "$dir"/iproxy 2222 22 &
    fi

    while ! (remote_cmd "echo connected" &> /dev/null); do
        sleep 1
    done

    touch .rd_in_progress
    
    if [ "$tweaks" = "1" ]; then
        echo "[*] Testing for baseband presence"
        if [ "$(remote_cmd "/usr/bin/mgask HasBaseband | grep -E 'true|false'")" = "true" ] && [ "${cpid}" == *"0x700"* ]; then
            disk=7
        elif [ "$(remote_cmd "/usr/bin/mgask HasBaseband | grep -E 'true|false'")" = "false" ]; then
            if [ "${cpid}" == *"0x700"* ]; then
                disk=6
            else
                disk=7
            fi
        fi

        if [ -z "$semi_tethered" ]; then
            disk=1
        fi

        if [[ "$version" == *"16"* ]]; then
            fs=disk1s$disk
        else
            fs=disk0s1s$disk
        fi

        echo "$disk" > .fs-"$deviceid"
    fi

    if [[ "$version" == *"16"* ]]; then
        # mount filesystems, no user data partition
        remote_cmd "/usr/bin/mount_filesystems_nouser"
    else
        # mount filesystems
        remote_cmd "/usr/bin/mount_filesystems"
    fi

    has_active=$(remote_cmd "ls /mnt6/active" 2> /dev/null)
    if [ ! "$has_active" = "/mnt6/active" ]; then
        echo "[!] Active file does not exist! Please use SSH to create it"
        echo "    /mnt6/active should contain the name of the UUID in /mnt6"
        echo "    When done, type reboot in the SSH session, then rerun the script"
        echo "    ssh root@localhost -p 2222"
        exit
    fi
    active=$(remote_cmd "cat /mnt6/active" 2> /dev/null)

    if [ "$restorerootfs" = "1" ]; then
        if [[ "$version" == *"16"* ]]; then
            echo "[!] --restorerootfs does not work on iOS 16 at this time"
            echo "    You must reboot into normal mode and Erase All Content and Settings"
            echo "    This should in theory restore rootfs your device"
            echo "    This is only a temporary fix until we can fix --restorerootfs"
            exit;
        else
            echo "[*] Removing Jailbreak"
            remote_cmd "/sbin/apfs_deletefs disk0s1s${disk} > /dev/null || true"
            remote_cmd "rm -f /mnt2/jb"
            remote_cmd "rm -rf /mnt2/cache /mnt2/lib"
            remote_cmd "rm -rf /mnt6/$active/procursus"
            remote_cmd "rm -f /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.raw /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.patched /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.im4p /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd"
            remote_cmd "mv /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcache.bak /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcache 2> /dev/null || true"
            remote_cmd "/bin/sync"
            remote_cmd "/usr/sbin/nvram auto-boot=true"
            rm -f BuildManifest.plist
            echo "[*] Done! Rebooting your device"
            remote_cmd "/sbin/reboot"
            exit;
        fi
    fi

    echo "[*] Dumping apticket"
    sleep 1
    remote_cp root@localhost:/mnt6/$active/System/Library/Caches/apticket.der blobs/"$deviceid"-"$version".der
    #remote_cmd "cat /dev/rdisk1" | dd of=dump.raw bs=256 count=$((0x4000)) 
    #"$dir"/img4tool --convert -s blobs/"$deviceid"-"$version".shsh2 dump.raw
    #rm dump.raw

    if [ "$semi_tethered" = "1" ]; then
        if [ -z "$skip_fakefs" ]; then
            echo "[*] Creating fakefs, this may take a while (up to 10 minutes)"
            remote_cmd 'mv -v /mnt1/usr/libexec/mobileactivationd /mnt1/usr/libexec/mobileactivationdBackup'
            sleep 1
            remote_cmd 'ldid -e /mnt1/usr/libexec/mobileactivationdBackup > /mnt1/usr/libexec/mob.plist'
            sleep 1
            "$dir"/sshpass -p 'alpine' scp -rP 2222 -o StrictHostKeyChecking=no ./mobileactivationd root@localhost:/mnt1/usr/libexec/mobileactivationd
            sleep 1
            remote_cmd 'chmod 755 /mnt1/usr/libexec/mobileactivationd'
            sleep 1
            remote_cmd 'ldid -S/mnt1/usr/libexec/mob.plist /mnt1/usr/libexec/mobileactivationd'
            sleep 1
            remote_cmd 'rm -v /mnt1/usr/libexec/mob.plist'
            sleep 1
            remote_cmd "/sbin/newfs_apfs -A -D -o role=r -v System /dev/disk0s1" && {
            sleep 2
            remote_cmd "/sbin/mount_apfs /dev/$fs /mnt8"
            sleep 1
            remote_cmd "cp -a /mnt1/. /mnt8/"
            sleep 1
            echo "[*] fakefs created, continuing..."
            } || remote_cmd "/sbin/mount_apfs /dev/$fs /mnt8" && echo "[*] Using the old fakefs, run restorerootfs if you need to clean it"
        fi
    fi

    if [[ ! "$version" == *"16"* ]]; then
        if [ -z "$no_install" ]; then
            tipsdir=$(remote_cmd "/usr/bin/find /mnt2/containers/Bundle/Application/ -name 'Tips.app'" 2> /dev/null)
            sleep 1
            if [ "$tipsdir" = "" ]; then
                echo "[!] Tips is not installed. Once your device reboots, install Tips from the App Store and retry"
                remote_cmd "/sbin/reboot"
                sleep 1
                _kill_if_running iproxy
                exit
            fi
            remote_cmd "/bin/mkdir -p /mnt1/private/var/root/temp"
            sleep 1
            remote_cmd "/bin/cp -r /usr/local/bin/loader.app/* /mnt1/private/var/root/temp"
            sleep 1
            remote_cmd "/bin/rm -rf /mnt1/private/var/root/temp/Info.plist /mnt1/private/var/root/temp/Base.lproj /mnt1/private/var/root/temp/PkgInfo"
            sleep 1
            remote_cmd "/bin/cp -rf /mnt1/private/var/root/temp/* $tipsdir"
            sleep 1
            remote_cmd "/bin/rm -rf /mnt1/private/var/root/temp"
            sleep 1
            remote_cmd "/usr/sbin/chown 33 $tipsdir/Tips"
            sleep 1
            remote_cmd "/bin/chmod 755 $tipsdir/Tips $tipsdir/palera1nHelper"
            sleep 1
            remote_cmd "/usr/sbin/chown 0 $tipsdir/palera1nHelper"
            sleep 1
            remote_cmd "/bin/mv /mnt8/Applications/Setup.app/Setup /mnt8/Applications/Setup.app/Setup.bak"
            sleep 1
            remote_cmd "/bin/cp -rf $tipsdir/* /mnt8/Applications/Setup.app/"
            sleep 1
            remote_cmd "/bin/mv /mnt8/Applications/Setup.app/Tips /mnt8/Applications/Setup.app/Setup"
            sleep 1
            remote_cmd '/usr/sbin/nvram allow-root-hash-mismatch=1'
        fi
    fi

    #remote_cmd "/usr/sbin/nvram allow-root-hash-mismatch=1"
    #remote_cmd "/usr/sbin/nvram root-live-fs=1"
    if [[ "$@" == *"--semi-tethered"* ]]; then
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram auto-boot=true"
    else
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram auto-boot=false"
    fi

    # lets actually patch the kernel
    echo "[*] Patching the kernel"
    remote_cmd "rm -f /mnt6/$active/kpf"
    if [[ "$version" == *"16"* ]]; then
        remote_cp binaries/Kernel16Patcher.ios root@localhost:/mnt6/$active/kpf
    else
        remote_cp binaries/Kernel15Patcher.ios root@localhost:/mnt6/$active/kpf
    fi
    remote_cmd "/usr/sbin/chown 0 /mnt6/$active/kpf"
    remote_cmd "/bin/chmod 755 /mnt6/$active/kpf"

    remote_cmd "rm -f /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.raw /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.patched /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.im4p /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd"
    if [ "$tweaks" = "1" ]; then
        remote_cmd "mv /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcache /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcache.bak"
    fi
    sleep 1

    # download the kernel
    echo "[*] Downloading BuildManifest"
    "$dir"/pzb -g BuildManifest.plist "$ipswurl"

    echo "[*] Downloading kernelcache"
    "$dir"/pzb -g "$(awk "/""$model""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" "$ipswurl"
    
    echo "[*] Patching kernelcache"
    mv kernelcache.release.* work/kernelcache
    if [[ "$deviceid" == "iPhone8"* ]] || [[ "$deviceid" == "iPad6"* ]] || [[ "$deviceid" == *'iPad5'* ]]; then
        python3 -m pyimg4 im4p extract -i work/kernelcache -o work/kcache.raw --extra work/kpp.bin
    else
        python3 -m pyimg4 im4p extract -i work/kernelcache -o work/kcache.raw
    fi
    sleep 1
    remote_cp work/kcache.raw root@localhost:/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/
    remote_cmd "/mnt6/$active/kpf /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.raw /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.patched"
    remote_cp root@localhost:/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.patched work/
    if [ "$tweaks" = "1" ]; then
        if [[ "$version" == *"16"* ]]; then
            "$dir"/Kernel64Patcher work/kcache.patched work/kcache.patched2 -e -o -u -l -t -h
        else
            "$dir"/Kernel64Patcher work/kcache.patched work/kcache.patched2 -e -l
        fi
    else
        "$dir"/Kernel64Patcher work/kcache.patched work/kcache.patched2 -a
    fi
    
    sleep 1
    if [[ "$deviceid" == *'iPhone8'* ]] || [[ "$deviceid" == *'iPad6'* ]] || [[ "$deviceid" == *'iPad5'* ]]; then
        python3 -m pyimg4 im4p create -i work/kcache.patched2 -o work/kcache.im4p -f krnl --extra work/kpp.bin --lzss
    else
        python3 -m pyimg4 im4p create -i work/kcache.patched2 -o work/kcache.im4p -f krnl --lzss
    fi
    sleep 1
    remote_cp work/kcache.im4p root@localhost:/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/
    remote_cmd "img4 -i /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.im4p -o /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd -M /mnt6/$active/System/Library/Caches/apticket.der"
    remote_cmd "rm -f /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.raw /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.patched /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.im4p"

    sleep 1
    has_kernelcachd=$(remote_cmd "ls /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd" 2> /dev/null)
    if [ "$has_kernelcachd" = "/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd" ]; then
        echo "[*] Custom kernelcache now exists!"
    else
        echo "[!] Custom kernelcache doesn't exist..? Please send a log and report this bug..."
    fi

    if [ "$tweaks" = "1" ]; then
        sleep 1
        if [ "$semi_tethered" = "1" ]; then
            remote_cmd "/sbin/mount_apfs /dev/$fs /mnt8 || true"
            di=8
        else
            disk=1
            di=1
        fi

        if [[ "$version" == *"16"* ]]; then
            remote_cmd "rm -rf /mnt$di/System/Library/Caches/com.apple.dyld"
            remote_cmd "ln -s /System/Cryptexes/OS/System/Library/Caches/com.apple.dyld /mnt$di/System/Library/Caches/"
        fi

        # iOS 16 stuff
        # if [[ "$version" == *"16"* ]]; then
        #     if [ -z "$semi_tethered" ]; then
        #         echo "[*] Performing iOS 16 fixes"
        #         sleep 1
        #         os_disk=$(remote_cmd "/usr/sbin/hdik /mnt6/cryptex1/current/os.dmg | head -3 | tail -1 | sed 's/ .*//'")
        #         sleep 1
        #         app_disk=$(remote_cmd "/usr/sbin/hdik /mnt6/cryptex1/current/app.dmg | head -3 | tail -1 | sed 's/ .*//'")
        #         sleep 1
        #         remote_cmd "/sbin/mount_apfs -o ro $os_disk /mnt2"
        #         sleep 1
        #         remote_cmd "/sbin/mount_apfs -o ro $app_disk /mnt9"
        #         sleep 1

        #         remote_cmd "rm -rf /mnt1/System/Cryptexes/App /mnt1/System/Cryptexes/OS"
        #         sleep 1
        #         remote_cmd "mkdir /mnt1/System/Cryptexes/App /mnt1/System/Cryptexes/OS"
        #         sleep 1
        #         remote_cmd "cp -a /mnt9/. /mnt1/System/Cryptexes/App"
        #         sleep 1
        #         remote_cmd "cp -a /mnt2/. /mnt1/System/Cryptexes/OS"
        #         sleep 1
        #         remote_cmd "rm -rf /mnt1/System/Cryptexes/OS/System/Library/Caches/com.apple.dyld"
        #         sleep 1
        #         remote_cmd "cp -a /mnt2/System/Library/Caches/com.apple.dyld /mnt1/System/Library/Caches/"
        #     fi
        # fi

        echo "[*] Copying files to rootfs"
        remote_cmd "rm -rf /mnt$di/jbin /mnt$di/.installed_palera1n"
        sleep 1
        remote_cmd "mkdir -p /mnt$di/jbin/binpack /mnt$di/jbin/loader.app"
        sleep 1

        cd other/rootfs/jbin

        if [[ "$version" == *"16"* ]]; then
            # download loader
            rm -rf loader.app
            curl -k -LO https://nightly.link/netsirkl64/loader/workflows/build/main/palera1n.zip
            unzip palera1n.zip -d .
            unzip palera1n.ipa -d .
            mv Payload/palera1nLoader.app loader.app
            rm -rf palera1n.zip loader.zip palera1n.ipa Payload
        fi

        # download jbinit files
        rm -f jb.dylib jbinit jbloader launchd
        curl -k -L https://nightly.link/palera1n/jbinit/workflows/build/main/rootfs.zip -o rfs.zip
        unzip rfs.zip -d .
        unzip rootfs.zip -d .
        rm rfs.zip rootfs.zip
        cd ../../..

        sleep 1
        remote_cp -r other/rootfs/* root@localhost:/mnt$di
        {
            echo "{"
            echo "    \"version\": \"${version} (${commit}_${branch})\","
            echo "    \"args\": \"$@\","
            echo "    \"pc\": \"$(uname) $(uname -r)\""
            echo "}"
        } > work/.installed_palera1n
        sleep 1
        remote_cp work/.installed_palera1n root@localhost:/mnt$di

        remote_cmd "ldid -s /mnt$di/jbin/launchd /mnt$di/jbin/jbloader /mnt$di/jbin/jb.dylib"
        remote_cmd "chmod +rwx /mnt$di/jbin/launchd /mnt$di/jbin/jbloader /mnt$di/jbin/post.sh"
        remote_cmd "tar -xvf /mnt$di/jbin/binpack/binpack.tar -C /mnt$di/jbin/binpack/"
        sleep 1
        remote_cmd "rm /mnt$di/jbin/binpack/binpack.tar"
    fi

    rm -rf work BuildManifest.plist
    mkdir work
    rm .rd_in_progress

    sleep 2
    echo "[*] Done! Rebooting your device"
    remote_cmd "/sbin/reboot"
    sleep 1
    _kill_if_running iproxy

    if [ "$semi_tethered" = "1" ]; then
        sleep 1
    elif [ -z "$tweaks" ]; then
        _wait normal
        sleep 5

        echo "[*] Switching device into recovery mode..."
        "$dir"/ideviceenterrecovery $(_info normal UniqueDeviceID)
    fi
    _wait recovery
    _dfuhelper
    sleep 2
fi

# ============
# Boot create
# ============

# Actually create the boot files
disk=$(cat .fs-"$deviceid")
if [[ "$version" == *"16"* ]]; then
    fs=disk1s$disk
else
    fs=disk0s1s$disk
fi

boot_args=""
if [ "$serial" = "1" ]; then
    boot_args="serial=3"
else
    boot_args="-v"
fi

if [[ "$deviceid" == iPhone9,[1-4] ]] || [[ "$deviceid" == "iPhone10"* ]]; then
    if [ ! -f boot-"$deviceid"/.payload ]; then
        rm -rf boot-"$deviceid"
    fi
else
    if [ ! -f boot-"$deviceid"/.local ]; then
        rm -rf boot-"$deviceid"
    fi
fi

if [ ! -f boot-"$deviceid"/ibot.img4 ]; then
    # Downloading files, and decrypting iBSS/iBEC
    rm -rf boot-"$deviceid"
    mkdir boot-"$deviceid"

    #echo "[*] Converting blob"
    #"$dir"/img4tool -e -s $(pwd)/blobs/"$deviceid"-"$version".shsh2 -m work/IM4M
    cd work

    # Do payload if on iPhone 7-10
    if [[ "$deviceid" == iPhone9,[1-4] ]] || [[ "$deviceid" == "iPhone10"* ]]; then
        if [[ "$version" == "16.0"* ]] || [[ "$version" == "15"* ]]; then
            newipswurl="$ipswurl"
        else
            newipswurl=$(curl -k -sL "https://api.appledb.dev/ios/iOS;20A392.json" | "$dir"/jq -r .devices\[\"$deviceid\"\].ipsw)
        fi

        echo "[*] Downloading BuildManifest"
        "$dir"/pzb -g BuildManifest.plist "$newipswurl"

        echo "[*] Downloading and decrypting iBoot"
        "$dir"/pzb -g "$(awk "/""$model""/{x=1}x&&/iBoot[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" "$newipswurl"
        "$dir"/gaster decrypt "$(awk "/""$model""/{x=1}x&&/iBoot[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]//')" ibot.dec

        echo "[*] Patching and signing iBoot"
        "$dir"/iBoot64Patcher ibot.dec ibot.patched

        if [[ "$deviceid" == iPhone9,[1-4] ]]; then
            "$dir"/iBootpatch2 --t8010 ibot.patched ibot.patched2
        else
            "$dir"/iBootpatch2 --t8015 ibot.patched ibot.patched2
        fi

        if [ "$os" = 'Linux' ]; then
            sed -i 's/\/\kernelcache/\/\kernelcachd/g' ibot.patched2
        else
            LC_ALL=C sed -i.bak -e 's/s\/\kernelcache/s\/\kernelcachd/g' ibot.patched2
            rm *.bak
        fi

        cd ..
        "$dir"/img4 -i work/ibot.patched2 -o boot-"$deviceid"/ibot.img4 -M blobs/"$deviceid"-"$version".der -A -T ibss

        touch boot-"$deviceid"/.payload
    else
        echo "[*] Downloading BuildManifest"
        "$dir"/pzb -g BuildManifest.plist "$ipswurl"

        echo "[*] Downloading and decrypting iBSS"
        "$dir"/pzb -g "$(awk "/""$model""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" "$ipswurl"
        "$dir"/gaster decrypt "$(awk "/""$model""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')" iBSS.dec
        
        echo "[*] Downloading and decrypting iBoot"
        "$dir"/pzb -g "$(awk "/""$model""/{x=1}x&&/iBoot[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" "$ipswurl"
        "$dir"/gaster decrypt "$(awk "/""$model""/{x=1}x&&/iBoot[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]//')" ibot.dec

        echo "[*] Patching and signing iBSS/iBoot"
        "$dir"/iBoot64Patcher iBSS.dec iBSS.patched
        if [ "$semi_tethered" = "1" ]; then
            if [ "$serial" = "1" ]; then
                "$dir"/iBoot64Patcher ibot.dec ibot.patched -b "serial=3 rd=$fs" -l
            else
                "$dir"/iBoot64Patcher ibot.dec ibot.patched -b "-v rd=$fs" -l
            fi
        else
            if [ "$serial" = "1" ]; then
                "$dir"/iBoot64Patcher ibot.dec ibot.patched -b "serial=3" -f
            else
                "$dir"/iBoot64Patcher ibot.dec ibot.patched -b "-v" -f
            fi
        fi

        if [ "$os" = 'Linux' ]; then
            sed -i 's/\/\kernelcache/\/\kernelcachd/g' ibot.patched
        else
            LC_ALL=C sed -i.bak -e 's/s\/\kernelcache/s\/\kernelcachd/g' ibot.patched
            rm *.bak
        fi
        cd ..
        "$dir"/img4 -i work/iBSS.patched -o boot-"$deviceid"/iBSS.img4 -M blobs/"$deviceid"-"$version".der -A -T ibss
        "$dir"/img4 -i work/ibot.patched -o boot-"$deviceid"/ibot.img4 -M blobs/"$deviceid"-"$version".der -A -T `if [[ "$cpid" == *"0x801"* ]]; then echo "ibss"; else echo "ibec"; fi`

        touch boot-"$deviceid"/.local
    fi
fi

# ============
# Boot device
# ============

sleep 2
_pwn
_reset
echo "[*] Booting device"
if [[ "$deviceid" == iPhone9,[1-4] ]] || [[ "$deviceid" == "iPhone10"* ]]; then
    sleep 1
    "$dir"/irecovery -f boot-"$deviceid"/ibot.img4
    sleep 3
    "$dir"/irecovery -c "dorwx"
    sleep 2
    if [[ "$deviceid" == iPhone9,[1-4] ]]; then
        "$dir"/irecovery -f other/payload/payload_t8010.bin
    else
        "$dir"/irecovery -f other/payload/payload_t8015.bin
    fi
    sleep 3
    "$dir"/irecovery -c "go"
    sleep 1
    "$dir"/irecovery -c "go xargs $boot_args"
    sleep 1
    "$dir"/irecovery -c "go xfb"
    sleep 1
    "$dir"/irecovery -c "go boot $fs"
else
    if [[ "$cpid" == *"0x801"* ]]; then
        sleep 1
        "$dir"/irecovery -f boot-"$deviceid"/ibot.img4
    else
        sleep 1
        "$dir"/irecovery -f boot-"$deviceid"/iBSS.img4
        sleep 4
        "$dir"/irecovery -f boot-"$deviceid"/ibot.img4
    fi
fi

if [ -z "$semi_tethered" ]; then
    sleep 2
    "$dir"/irecovery -c fsboot
fi

if [ -d "logs" ]; then
    cd logs
    for file in *.log; do
        if [[ "$file" != "SUCCESS_"* ]] && [[ "$file" != "FAIL_"* ]]; then
            mv "$file" SUCCESS_${file}
        fi
    done
    cd ..
fi

rm -rf work rdwork
echo ""
echo "Done!"
echo "The device should now boot to iOS"
echo "When you unlock the device, it will respring about 30 seconds after"
echo "If this is your first time jailbreaking, open the new palera1n app, then press Install"
echo "Otherwise, press Do All in the settings section of the app"
echo "If you have any issues, please join the Discord server and ask for help: https://dsc.gg/palera1n"
echo "Enjoy!"

} | tee logs/"$(date +%T)"-"$(date +%F)"-"$(uname)"-"$(uname -r)".log
