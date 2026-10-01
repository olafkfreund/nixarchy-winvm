{ pkgs, ... }:

{
  packages = [
    pkgs.gh
    pkgs.p7zip
    pkgs.qemu_kvm
    pkgs.OVMF
    pkgs.python3
    pkgs.qt6Packages.qtdeclarative
  ];

  scripts.validate.exec = ''
    plugin_dir=$(mktemp -d)
    qml_import_dir=$(mktemp -d)
    trap 'rm -rf "$plugin_dir" "$qml_import_dir"' EXIT
    cp manifest.json Menu.qml WinVmService.qml winvm-launcher.sh winvm-stats.sh "$plugin_dir/"
    omarchy plugin validate "$plugin_dir"
    ln -s "''${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$qml_import_dir/qs"
    qt_import_path=$(dirname "$(readlink -f "$(command -v qmllint)")")/../lib/qt-6/qml
    quickshell_import_path=$(dirname "$(readlink -f "$(command -v qs)")")/../lib/qt-6/qml
    qmllint -I "$qml_import_dir" \
      -I "$qt_import_path" \
      -I "$quickshell_import_path" \
      -I "''${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
      "$plugin_dir/Menu.qml" "$plugin_dir/WinVmService.qml"
    bash -n winvm-launcher.sh winvm-stats.sh dev/sync
    python3 -m py_compile dev/vm-qmp.py
  '';

  scripts.vm-install.exec = ''
    set -euo pipefail
    vm_dir="''${NIXARCHY_TRY_DIR:-$HOME/.local/share/nixarchy-winvm/nixarchy-try}"
    mkdir -p "$vm_dir"
    args=(--net --memory 8192 --cpus 4)
    if [[ "''${VM_FRESH:-0}" == 1 ]]; then args+=(--fresh); fi
    cd "$vm_dir"
    nix run github:olafkfreund/nixarchy#try -- "''${args[@]}"
  '';

  scripts.vm-install-unattended.exec = ''
    set -euo pipefail
    vm_dir="''${NIXARCHY_TRY_DIR:-$HOME/.local/share/nixarchy-winvm/nixarchy-try}"
    disk="$vm_dir/nixarchy-try.qcow2"
    vars="$vm_dir/nixarchy-try-efivars.fd"
    mkdir -p "$vm_dir"
    if [[ -e "$disk" || -e "$vars" ]]; then
      [[ "''${VM_FRESH:-0}" == 1 ]] || {
        echo "VM state already exists; use VM_FRESH=1 to replace it." >&2
        exit 1
      }
      rm -f "$disk" "$vars"
    fi

    answer_url=$(printf '%s\n' \
      'device=/dev/vda' \
      'disk_mode=whole' \
      'encrypt=no' \
      'hostname=nixarchy-winvm' \
      'username=demo' \
      'password=demo' \
      'timezone=Europe/London' \
      'keymap=us' | gh gist create --filename nixarchy-winvm-answers.txt -)
    gist_id=''${answer_url##*/}
    gist_user=$(gh api user --jq .login)
    answer_url="https://gist.githubusercontent.com/$gist_user/$gist_id/raw/nixarchy-winvm-answers.txt"
    cleanup() { gh gist delete "$gist_id" >/dev/null 2>&1 || true; }
    trap cleanup EXIT

    iso=$(find "$(nix build --no-link --print-out-paths github:olafkfreund/nixarchy#iso-net)" -type f -name '*.iso' -print -quit)
    kernel_entry=$(7z e -so "$iso" EFI/BOOT/grub.cfg | awk '/^[[:space:]]+linux .*bzImage / { print; exit }')
    kernel_iso_path="''${kernel_entry#*linux }"
    kernel_iso_path="''${kernel_iso_path%% *}"
    kernel_iso_path="''${kernel_iso_path#/}"
    kernel_iso_path="''${kernel_iso_path//\/\//\/}"
    initrd_iso_path=$(7z e -so "$iso" EFI/BOOT/grub.cfg | awk '/^[[:space:]]+initrd / { print $2; exit }')
    initrd_iso_path="''${initrd_iso_path#/}"
    initrd_iso_path="''${initrd_iso_path//\/\//\/}"
    kernel_args="''${kernel_entry#*bzImage }"
    kernel_args="''${kernel_args//\$\{isoboot\}/}"
    kernel="$vm_dir/nixarchy-installer-kernel"
    initrd="$vm_dir/nixarchy-installer-initrd"
    7z e -so "$iso" "$kernel_iso_path" > "$kernel"
    7z e -so "$iso" "$initrd_iso_path" > "$initrd"
    qemu-img create -q -f qcow2 "$disk" 32G
    install -m 0644 "${pkgs.OVMF.fd}/FV/OVMF_VARS.fd" "$vars"
    accel=(-accel tcg -cpu max)
    if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
      accel=(-accel kvm -cpu host)
    fi
    qemu-system-x86_64 \
      -name nixarchy-try \
      -machine q35 \
      -m 8192 -smp 4 \
      "''${accel[@]}" \
      -drive "if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd" \
      -drive "if=pflash,format=raw,file=$vars" \
      -drive "id=hd0,if=none,format=qcow2,file=$disk" \
      -device virtio-blk-pci,drive=hd0,bootindex=1 \
      -device virtio-scsi-pci,id=scsi0 \
      -drive "id=cd0,if=none,media=cdrom,readonly=on,format=raw,file=$iso" \
      -device scsi-cd,bus=scsi0.0,drive=cd0 \
      -display gtk -device virtio-vga \
      -device qemu-xhci -device usb-tablet \
      -nic user,model=virtio-net-pci \
      -kernel "$kernel" -initrd "$initrd" \
      -append "$kernel_args nixarchy.answers=$answer_url"
  '';

  scripts.vm-boot.exec = ''
    set -euo pipefail
    vm_dir="''${NIXARCHY_TRY_DIR:-$HOME/.local/share/nixarchy-winvm/nixarchy-try}"
    test -f "$vm_dir/nixarchy-try.qcow2" || {
      echo "VM disk not found; run: devenv shell -- vm-install" >&2
      exit 1
    }
    cd "$vm_dir"
    nix run github:olafkfreund/nixarchy#try -- --boot --memory 8192 --cpus 4
  '';

  scripts.vm-boot-controlled.exec = ''
    set -euo pipefail
    vm_dir="''${NIXARCHY_TRY_DIR:-$HOME/.local/share/nixarchy-winvm/nixarchy-try}"
    repo_dir="''${WINVM_REPO_DIR:-$PWD}"
    display="''${WINVM_DISPLAY:-gtk}"
    disk="$vm_dir/nixarchy-try.qcow2"
    vars="$vm_dir/nixarchy-try-efivars.fd"
    qmp="$vm_dir/nixarchy-try.qmp.sock"
    test -f "$disk" || { echo "VM disk not found; run: vm-install-unattended" >&2; exit 1; }
    rm -f "$qmp"
    accel=(-accel tcg -cpu max)
    if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
      accel=(-accel kvm -cpu host)
    fi
    cd "$vm_dir"
    exec qemu-system-x86_64 \
      -name nixarchy-try \
      -machine q35 -m 8192 -smp 4 "''${accel[@]}" \
      -drive "if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd" \
      -drive "if=pflash,format=raw,file=$vars" \
      -drive "id=hd0,if=none,format=qcow2,file=$disk" \
      -device virtio-blk-pci,drive=hd0,bootindex=0 \
      -device virtio-vga \
      -qmp "unix:$qmp,server=on,wait=off" \
      -virtfs "local,path=$repo_dir,mount_tag=winvmrepo,security_model=none,readonly=on" \
      -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
      -display "$display"
  '';

  scripts.vm-qmp.exec = ''
    set -euo pipefail
    vm_dir="''${NIXARCHY_TRY_DIR:-$HOME/.local/share/nixarchy-winvm/nixarchy-try}"
    qmp="$vm_dir/nixarchy-try.qmp.sock"
    test -S "$qmp" || { echo "QMP socket not found: $qmp" >&2; exit 1; }
    python3 "$DEVENV_ROOT/dev/vm-qmp.py" "$qmp" "$@"
  '';

  scripts.vm-stop.exec = ''
    set -euo pipefail
    pid=$(ps -eo pid=,args= | awk '$0 ~ /qemu-system-x86_64/ && $0 ~ /-name nixarchy-try/ { print $1; exit }')
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "Stopped nixarchy test VM ($pid)."
    else
      echo "nixarchy test VM is not running."
    fi
  '';
}
