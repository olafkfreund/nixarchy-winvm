{ pkgs, ... }:

{
  packages = [
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
  '';
}
