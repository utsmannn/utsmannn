#!/bin/zsh
set -e

spinner_pid=

trap stop_spinner EXIT

function start_spinner() {
  stop_spinner
  spinchars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

  { while :; do for X in "${spinchars[@]}"; do
    echo -en "\r$1 $X "
    sleep 0.1
  done; done & } 2>/dev/null
  spinner_pid=$!
}

function stop_spinner() {
  { kill -9 $spinner_pid && wait; } 2>/dev/null
  echo -en "\033[2K\r"
}

function main() {
  remote_dir="$HOME/.android-remote-build"

  if [ ! -d "$remote_dir" ]; then
    mkdir -p "$remote_dir"
  fi

  remotesh_url="https://raw.githubusercontent.com/utsmannn/utsmannn/master/remote.sh"
  remotesh_updater_url="https://raw.githubusercontent.com/utsmannn/utsmannn/master/remotesh-updater.sh"
  gcloud_compute_url="https://raw.githubusercontent.com/utsmannn/utsmannn/master/gcloud-compute.sh"
  remote_exclude_url="https://raw.githubusercontent.com/utsmannn/utsmannn/master/remote-exclude-list.txt"
  remote_version_url="https://raw.githubusercontent.com/utsmannn/utsmannn/master/remote-versioning.txt"

  start_spinner "Updating remote.sh"
  rm $remote_dir/remote.sh $remote_dir/gcloud-compute.sh $remote_dir/remote-exclude-list.txt $remote_dir/remotesh-updater.sh 2>/dev/null
  curl --header 'PRIVATE-TOKEN: bx_xHHKxFUGniHfrxsdr' --header 'Cache-Control: no-cache, no-store' $remotesh_url --output $remote_dir/remote.sh 2>/dev/null
  curl --header 'PRIVATE-TOKEN: bx_xHHKxFUGniHfrxsdr' --header 'Cache-Control: no-cache, no-store' $remote_version_url --output $remote_dir/remote-versioning.txt 2>/dev/null
  curl --header 'PRIVATE-TOKEN: bx_xHHKxFUGniHfrxsdr' --header 'Cache-Control: no-cache, no-store' $remotesh_updater_url --output $remote_dir/remotesh-updater.sh 2>/dev/null

  sleep 2
  start_spinner "Updating gcloud_compute.sh"
  curl --header 'PRIVATE-TOKEN: bx_xHHKxFUGniHfrxsdr' --header 'Cache-Control: no-cache, no-store' $gcloud_compute_url --output $remote_dir/gcloud-compute.sh 2>/dev/null

  sleep 2
  start_spinner "Updating remote-exclude-list.txt"
  curl --header 'PRIVATE-TOKEN: bx_xHHKxFUGniHfrxsdr' --header 'Cache-Control: no-cache, no-store' $remote_exclude_url --output $remote_dir/remote-exclude-list.txt 2>/dev/null

  sleep 2
  start_spinner "Setting up permissions"
  chmod +x $HOME/.android-remote-build/remote.sh
  chmod +x $HOME/.android-remote-build/remotesh-updater.sh
  chmod +x $HOME/.android-remote-build/gcloud-compute.sh
}

main "$@"
exit
