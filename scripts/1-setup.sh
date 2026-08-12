#!/usr/bin/env bash
#github-action genshdoc
#
# @file Setup
# @brief Configures installed system, installs base packages, and creates user. 
echo -ne "
-------------------------------------------------------------------------
   █████╗ ██████╗  ██████╗██╗  ██╗████████╗██╗████████╗██╗   ██╗███████╗
  ██╔══██╗██╔══██╗██╔════╝██║  ██║╚══██╔══╝██║╚══██╔══╝██║   ██║██╔════╝
  ███████║██████╔╝██║     ███████║   ██║   ██║   ██║   ██║   ██║███████╗
  ██╔══██║██╔══██╗██║     ██╔══██║   ██║   ██║   ██║   ██║   ██║╚════██║
  ██║  ██║██║  ██║╚██████╗██║  ██║   ██║   ██║   ██║   ╚██████╔╝███████║
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝   ╚═╝    ╚═════╝ ╚══════╝
-------------------------------------------------------------------------
                    Automated Arch Linux Installer
                        SCRIPTHOME: ArchTitus
-------------------------------------------------------------------------
"
source $HOME/ArchTitus/configs/setup.conf
echo -ne "
-------------------------------------------------------------------------
                    Network Setup 
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed networkmanager dhclient
systemctl enable --now NetworkManager
echo -ne "
-------------------------------------------------------------------------
                    Setting up mirrors for optimal download 
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed pacman-contrib curl
pacman -S --noconfirm --needed reflector rsync grub arch-install-scripts git
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

nc=$(grep -c ^processor /proc/cpuinfo)
echo -ne "
-------------------------------------------------------------------------
                    You have " $nc" cores. And
			changing the makeflags for "$nc" cores. Aswell as
				changing the compression settings.
-------------------------------------------------------------------------
"
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[  $TOTAL_MEM -gt 8000000 ]]; then
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
fi
echo -ne "
-------------------------------------------------------------------------
                    Setup Language to US and set locale  
-------------------------------------------------------------------------
"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
timedatectl --no-ask-password set-timezone ${TIMEZONE}
timedatectl --no-ask-password set-ntp 1
localectl --no-ask-password set-locale LANG="en_US.UTF-8" LC_TIME="en_US.UTF-8"
ln -s /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
# Set keymaps
localectl --no-ask-password set-keymap ${KEYMAP}

# Add sudo no password rights
sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

#Add parallel downloading
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

#Enable multilib
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm --needed

echo -ne "
-------------------------------------------------------------------------
                    Installing Base System  
-------------------------------------------------------------------------
"
# sed $INSTALL_TYPE is using install type to check for MINIMAL installation, if it's true, stop
# stop the script and move on, not installing any more packages below that line
if [[ ! $DESKTOP_ENV == server ]]; then
  sed -n '/'$INSTALL_TYPE'/q;p' $HOME/ArchTitus/pkg-files/pacman-pkgs.txt | while read line
  do
    if [[ ${line} == '--END OF MINIMAL INSTALL--' ]]; then
      # If selected installation type is FULL, skip the --END OF THE MINIMAL INSTALLATION-- line
      continue
    fi
    echo "INSTALLING: ${line}"
    sudo pacman -S --noconfirm --needed ${line}
  done
fi
echo -ne "
-------------------------------------------------------------------------
                    Installing Microcode
-------------------------------------------------------------------------
"
# determine processor type and install microcode
proc_type=$(lscpu)
if grep -E "GenuineIntel" <<< ${proc_type}; then
    echo "Installing Intel microcode"
    pacman -S --noconfirm --needed intel-ucode
    proc_ucode=intel-ucode.img
elif grep -E "AuthenticAMD" <<< ${proc_type}; then
    echo "Installing AMD microcode"
    pacman -S --noconfirm --needed amd-ucode
    proc_ucode=amd-ucode.img
fi

echo -ne "
-------------------------------------------------------------------------
                    Installing Fallback Kernel
-------------------------------------------------------------------------
"
# Installed here rather than via pkg-files/pacman-pkgs.txt because that list is
# skipped entirely when DESKTOP_ENV=server (see the guard above) -- and a
# headless box is exactly where a second bootable kernel matters most, since
# there is no desktop to fall back to and possibly no easy console access.
#
# Rolling release plus DKMS kernel modules means eventually meeting a kernel
# that will not build. A known-good LTS entry already in the GRUB menu turns
# that from an unbootable machine into a reboot. Headers included so
# nvidia-open-dkms builds against this kernel too.
pacman -S --noconfirm --needed linux-lts linux-lts-headers

echo -ne "
-------------------------------------------------------------------------
                    Installing Graphics Drivers
-------------------------------------------------------------------------
"
# Graphics Drivers find and install
#
# NOTE: these are deliberately independent `if` blocks rather than an elif
# chain. Hybrid machines (Intel iGPU + NVIDIA dGPU is extremely common) need
# BOTH stacks installed -- with an elif, NVIDIA matched first and the box was
# left with no mesa/vulkan-intel at all, losing iGPU video decode and any
# fallback if the NVIDIA module failed to build.
gpu_type=$(lspci)

if grep -E "NVIDIA|GeForce" <<< ${gpu_type}; then
    echo "Installing NVIDIA drivers (open kernel modules, DKMS)"
    # nvidia-open-dkms instead of nvidia:
    #   - DKMS rebuilds against ANY kernel (linux-lts, linux-zen, linux-cachyos).
    #     The plain `nvidia` package ships prebuilt modules for the stock `linux`
    #     kernel only, so swapping kernels later gives you an unbootable system.
    #   - The open modules are NVIDIA's recommended path on Turing and newer,
    #     and behave considerably better under Wayland.
    # linux-headers is listed explicitly so DKMS can build regardless of the
    # order the package lists get applied in.
    pacman -S --noconfirm --needed nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
        nvidia-settings linux-headers

    # Early KMS. Without the nvidia modules in the initramfs the console handoff
    # to the display manager flickers and the Plymouth splash configured in
    # 3-post-setup.sh does not render on NVIDIA hardware at all.
    if ! grep -q 'nvidia_drm' /etc/mkinitcpio.conf; then
        sed -i 's/^MODULES=(\(.*\))$/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
        sed -i 's/^MODULES=( /MODULES=(/' /etc/mkinitcpio.conf
        mkinitcpio -P
    fi

    # NOT running `nvidia-xconfig` here, on purpose.
    #
    # It writes a static /etc/X11/xorg.conf containing hardcoded metamodes and
    # monitor sync ranges. That file then fights the desktop's own display
    # manager (mutter/kwin) on every login, and goes silently stale the moment
    # monitors are added, removed or rearranged -- producing display layouts
    # that cannot be fixed from the GUI. Modern Arch autodetects outputs
    # correctly, and Wayland ignores xorg.conf entirely.

    if [[ ${INSTALL_CUDA} == "yes" ]]; then
        echo "Installing CUDA toolkit"
        pacman -S --noconfirm --needed cuda cudnn
    fi
fi

if lspci | grep 'VGA' | grep -E "Radeon|AMD"; then
    pacman -S --noconfirm --needed xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon \
        libva-mesa-driver mesa lib32-mesa
fi

if grep -E "Integrated Graphics Controller|Intel Corporation UHD|Intel Corporation .* Graphics" <<< ${gpu_type}; then
    pacman -S --noconfirm --needed mesa lib32-mesa vulkan-intel lib32-vulkan-intel \
        intel-media-driver libva-intel-driver libvdpau-va-gl libva-utils
fi

if [[ ${INSTALL_CACHYOS_KERNEL} == "yes" ]]; then
echo -ne "
-------------------------------------------------------------------------
                    Installing CachyOS Kernel
-------------------------------------------------------------------------
"
    # Uses the vendor's own bootstrap script rather than hand-adding the repo,
    # so the signing key is imported and locally signed the way upstream
    # intends. Everything here is non-fatal on purpose: a third-party mirror
    # being unreachable must never take down the whole install. Worst case the
    # machine boots stock `linux` with `linux-lts` as backup, exactly as if the
    # option had been declined.
    (
        set -e
        # curl is not part of the pacstrap set in 0-preinstall.sh, so it is not
        # guaranteed to exist inside the chroot. xz is needed to unpack .tar.xz.
        pacman -S --noconfirm --needed curl xz
        cachy_tmp=$(mktemp -d)
        cd "${cachy_tmp}"
        curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
        tar xf cachyos-repo.tar.xz
        cd cachyos-repo
        # `yes |` is load-bearing: cachyos-repo.sh shells out to `pacman -U`
        # WITHOUT --noconfirm and runs under `set -e`. Unattended, that prompt
        # reads EOF, the script aborts before adding any repo, and the kernel
        # install then fails with "target not found: linux-cachyos".
        # Invoked via bash so a missing exec bit in the tarball is not fatal,
        # and from inside its own directory because it references
        # ./install-repo.awk by relative path.
        yes | bash ./cachyos-repo.sh --install

        # Keep the kernels, drop the distro. cachyos-repo.sh also wires up the
        # v3/v4 rebuilds of core/extra; disabling them leaves the base system
        # sourced from stock Arch while [cachyos] still provides linux-cachyos.
        awk '
            /^\[/ { in_opt = ($0 ~ /^\[cachyos(-core|-extra)?-v[34]\]/) }
            { if (in_opt && NF && $0 !~ /^#/) print "#" $0; else print }
        ' /etc/pacman.conf > /etc/pacman.conf.cachytrim
        mv /etc/pacman.conf.cachytrim /etc/pacman.conf

        pacman -Sy --noconfirm
        # headers included so the nvidia-open-dkms modules build for this kernel too
        pacman -S --noconfirm --needed linux-cachyos linux-cachyos-headers
    ) && echo "CachyOS kernel installed" \
      || echo "WARNING: CachyOS kernel setup failed -- continuing with linux + linux-lts"
fi

if [[ ${INSTALL_CHAOTIC_AUR} == "yes" ]]; then
echo -ne "
-------------------------------------------------------------------------
                    Enabling Chaotic-AUR
-------------------------------------------------------------------------
"
    # Runs before 2-user.sh, so the AUR helper picks up prebuilt binaries for
    # anything in pkg-files/aur-pkgs.txt instead of compiling it.
    (
        set -e
        # The full 40-character fingerprint, deliberately, rather than the short
        # key ID upstream's docs use. This key gets --lsign-key'd, which grants
        # it authority over package signatures on this machine, and short IDs
        # are collidable. Verified against keyserver.ubuntu.com as belonging to
        # Pedro Henrique Lara Campos (PedroHLC), a Chaotic-AUR maintainer.
        CHAOTIC_KEY="EF925EA60F33D0CB85C44AD13056513887B78AEB"
        pacman-key --recv-key "${CHAOTIC_KEY}" --keyserver keyserver.ubuntu.com
        pacman-key --lsign-key "${CHAOTIC_KEY}"

        pacman -U --noconfirm \
            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

        # Appended at the END of pacman.conf on purpose. pacman resolves by repo
        # order, so keeping chaotic-aur last means official Arch packages always
        # win and chaotic-aur only supplies what Arch does not carry.
        if ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
            printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' >> /etc/pacman.conf
        fi

        pacman -Sy --noconfirm
    ) && echo "Chaotic-AUR enabled" \
      || echo "WARNING: Chaotic-AUR setup failed -- continuing without it"
fi
#SETUP IS WRONG THIS IS RUN
if ! source $HOME/ArchTitus/configs/setup.conf; then
	# Loop through user input until the user gives a valid username
	while true
	do 
		read -p "Please enter username:" username
		# username regex per response here https://unix.stackexchange.com/questions/157426/what-is-the-regex-to-validate-linux-users
		# lowercase the username to test regex
		if [[ "${username,,}" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]
		then 
			break
		fi 
		echo "Incorrect username."
	done 
# convert name to lowercase before saving to setup.conf
echo "username=${username,,}" >> ${HOME}/ArchTitus/configs/setup.conf

    #Set Password
    read -p "Please enter password:" password
echo "password=${password,,}" >> ${HOME}/ArchTitus/configs/setup.conf

    # Loop through user input until the user gives a valid hostname, but allow the user to force save 
	while true
	do 
		read -p "Please name your machine:" name_of_machine
		# hostname regex (!!couldn't find spec for computer name!!)
		if [[ "${name_of_machine,,}" =~ ^[a-z][a-z0-9_.-]{0,62}[a-z0-9]$ ]]
		then 
			break 
		fi 
		# if validation fails allow the user to force saving of the hostname
		read -p "Hostname doesn't seem correct. Do you still want to save it? (y/n)" force 
		if [[ "${force,,}" = "y" ]]
		then 
			break 
		fi 
	done 

    echo "NAME_OF_MACHINE=${name_of_machine,,}" >> ${HOME}/ArchTitus/configs/setup.conf
fi
echo -ne "
-------------------------------------------------------------------------
                    Adding User
-------------------------------------------------------------------------
"
if [ $(whoami) = "root"  ]; then
    groupadd libvirt
    useradd -m -G wheel,libvirt -s /bin/bash $USERNAME 
    echo "$USERNAME created, home directory created, added to wheel and libvirt group, default shell set to /bin/bash"

# use chpasswd to enter $USERNAME:$password
    echo "$USERNAME:$PASSWORD" | chpasswd
    echo "$USERNAME password set"

	cp -R $HOME/ArchTitus /home/$USERNAME/
    chown -R $USERNAME: /home/$USERNAME/ArchTitus
    echo "ArchTitus copied to home directory"

# enter $NAME_OF_MACHINE to /etc/hostname
	echo $NAME_OF_MACHINE > /etc/hostname
else
	echo "You are already a user proceed with aur installs"
fi
if [[ ${FS} == "luks" ]]; then
# Making sure to edit mkinitcpio conf if luks is selected
# add encrypt in mkinitcpio.conf before filesystems in hooks
    sed -i 's/filesystems/encrypt filesystems/g' /etc/mkinitcpio.conf
# regenerate every initramfs preset -- `-p linux` silently skips any other
# kernel (linux-lts, linux-zen, linux-cachyos), leaving it unbootable under LUKS
    mkinitcpio -P
fi
echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 2-user.sh
-------------------------------------------------------------------------
"
