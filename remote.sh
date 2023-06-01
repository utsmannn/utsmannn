#!/bin/bash
set -e

CURRENT_DIR=$(pwd)
CURRENT_FOLDER=$(basename $(pwd))

GRADLE_TASK=
APK_NAME=
APK_DIR=
BUILD_TYPE="Debug"
PACKAGE_NAME=

spinner_pid=
daemon_pid=
remote_home=
remote_parent_directory=
remote_directory=
state=

is_android_project=0
is_has_parent=0
is_has_project=0
is_adb_skipped=0

is_build=0
is_full_build=0
is_install=0
is_reinstall=0
is_launch=0

is_scan_initial_run=0

function help() {
  echo "Remote Android Development"
  echo
  echo "Bash script for remote Android dev. Builds, installs, runs APKs"
  echo "from VM instance, improves perform. Useful tool for developers by reducing"
  echo "the resource-intensive tasks running locally."
  echo
  echo "Options:"
  echo "  -h     Print this help."
  echo "  -t     Input build type [alpha|debug|release], default is 'debug'"
  echo "  -b     Build, gradle task 'assemble' will be run in vm instance"
  echo "  -f     Full build, gradle task 'build' will be run in vm instance"
  echo "  -i     Install apk"
  echo "  -r     Reinstall apk"
  echo "  -l     Launch apk"
  echo "  -c     Custom gradle task"
  echo
  echo "Sample:"
  echo "./remote.sh -b -i -l"
  echo "Same as 'run' button in Android Studio, will be execute task assembleDebug, install and launch."
  echo

  is_scan_initial_run=1
  check_initial_run
}

gcloud_compute_path="$HOME/.android-remote-build/gcloud-compute.sh"

function gcloud_ssh() {
  gcloud compute ssh $1 --zone asia-southeast2-a --internal-ip --command "$2"
}

function verify_android_project() {
  file="local.properties"
  keyword="sdk.dir"

  if [ -f "$file" ]; then
    content=$(cat "$file")

    if echo "$content" | grep -q "$keyword"; then
      is_android_project=1
    else
      is_android_project=0
    fi
  else
    is_android_project=0
  fi
}

function main() {
  if [ -z $1 ]; then
    help
    exit 1
  fi

  while getopts ":ht:bilrfc:" opt; do
    case ${opt} in
    h)
      help
      exit 1
      ;;
    t)
      case $OPTARG in
      debug)
        BUILD_TYPE="Debug"
        ;;
      release)
        BUILD_TYPE="Release"
        ;;
      alpha)
        BUILD_TYPE="Alpha"
        ;;
      *)
        echo "Invalid mode: $OPTARG" >&2
        exit 1
        ;;
      esac
      ;;
    b)
      is_build=1
      ;;
    i)
      is_install=1
      ;;
    l)
      is_launch=1
      ;;
    r)
      is_reinstall=1
      ;;
    f)
      if [ $is_build -eq 1 ]; then
        echo "> Remote: full build skipped because 'build' argument existing"
        is_full_build=1
        GRADLE_TASK="build -x test"
      else
        GRADLE_TASK=$OPTARG
      fi
      ;;
    c)
      if [ $is_build -eq 1 ]; then
        echo "> Remote: custom task '$OPTARG' skipped because 'build' argument existing"
        GRADLE_TASK=$OPTARG
      else
        GRADLE_TASK=$OPTARG
      fi
      if [ $is_full_build -eq 1 ]; then
        echo "> Remote: custom task '$OPTARG' skipped because 'full build' argument existing"
        GRADLE_TASK=$OPTARG
      else
        GRADLE_TASK=$OPTARG
      fi
      ;;
    \?)
      echo "Invalid option: -$OPTARG" 1>&2
      exit 1
      ;;
    :)
      case $OPTARG in
      "c")
        echo "Custom task must be provided, like 'remote.sh -c assembleDebug'"
        ;;
      "t")
        echo "Build type must be provided, (alpha, debug, or release) with lowercase"
        ;;
      esac
      exit 1
      ;;
    esac
  done

  if [ $is_build -eq 1 ]; then
    GRADLE_TASK="assemble$BUILD_TYPE"
  fi

  echo "Remote run: $GRADLE_TASK on $REMOTE_APP module"
  if [ -n "$GRADLE_TASK" ]; then
    execute
  fi

  sleep 3

  if [ $is_install -eq 1 ]; then
    if [ $is_reinstall -eq 1 ]; then
      replace_apk
    else
      install_apk
    fi
  fi

  if [ $is_launch -eq 1 ]; then
    if [ $is_install -eq 1 ]; then
      echo "Launch app"
    else
      echo "Launch app without install"
    fi
    launch_apk
  fi
}

function stopping_gradle {
  start_spinner "> Remote: Stopping GradleDaemon"
  sleep 2
  daemon_process=$(gcloud_ssh $REMOTE_VM 'pgrep -fa GradleDaemon')
  daemon_pid=$(echo $daemon_process | cut -d' ' -f1)
  gcloud_ssh $REMOTE_VM "kill $daemon_pid"
  stop_spinner
}

function stop_task {
  stop_spinner

  case $state in
  "upload")
    exit 1
    ;;
  "run_task")
    stopping_gradle
    echo "> Remote stopped by user"
    ;;
  "done")
    stopping_gradle
    echo "> Remote done"
    ;;
  "cancel")
    echo "> Remote cancelled!"
    ;;
  *)
    exit 1
    ;;
  esac
}

trap stop_task EXIT

function start_spinner() {
  spinchars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

  { while :; do for X in "${spinchars[@]}"; do
    echo -en "\r$1 $X"
    sleep 0.1
  done; done & } 2>/dev/null
  spinner_pid=$!
}

function stop_spinner() {
  { kill -9 $spinner_pid && wait; } 2>/dev/null
  echo -en "\033[2K\r"
}

function check_project_exist() {
  remote_directory="$remote_home/remote/$CURRENT_FOLDER"
  if gcloud_ssh $REMOTE_VM "[ -d $remote_directory ]"; then
    is_has_project=1
  else
    is_has_project=0
  fi
}

function execute() {
  check_initial_run

  if [ $is_has_parent -eq 1 ]; then
    check_project_exist
  else
    echo "> Remote: initial rsync"
  fi

  if [ $is_has_project -eq 1 ]; then
    echo $state
    echo "> Remote: Initialize"
  fi

  upload
  run_task
  download
}

function upload() {
  state="upload"
  start_spinner "> Remote: Sync remote from local"
  rsync -avz -q --delete --exclude-from ~/.android-remote-build/remote-exclude-list.txt -e "bash $gcloud_compute_path" "$CURRENT_DIR" $REMOTE_VM:~/remote 2>/dev/null

  stop_spinner
}

function run_task() {
  state="run_task"
  echo "> Remote: Run gradle task :$REMOTE_APP:$GRADLE_TASK"
  android_sdk=$(gcloud_ssh $REMOTE_VM "bash /opt/get_android_home.sh")
  gcloud_ssh $REMOTE_VM "cd $remote_home/remote/$CURRENT_FOLDER && echo \"sdk.dir=$android_sdk\" >local.properties && java --version && sdkmanager --list_installed && ./gradlew clean :$REMOTE_APP:$GRADLE_TASK "
}

function download() {
  echo ' '
  start_spinner "> Remote: Sync local from remote"
  rsync -avz -q --delete --exclude-from ~/.android-remote-build/remote-exclude-list.txt -e "bash $gcloud_compute_path" $REMOTE_VM:~/remote/$CURRENT_FOLDER .. 2>/dev/null

  stop_spinner
  state="done"

}

function check_initial_run() {
  start_spinner "Verify android project"
  verify_android_project
  sleep 2
  stop_spinner

  if [ $is_android_project -eq 0 ]; then
    echo "This directory not android project"
    state="cancel"
    exit 1
  fi

  start_spinner "Checking requirement"
  sleep 3

  if [ -z $REMOTE_VM ]; then
    stop_spinner
    echo "Error: Environment variable of 'REMOTE_VM' not found."

    if [ $is_scan_initial_run -eq 0 ]; then
      state="cancel"
      exit 1
    fi
  else
    stop_spinner
  fi

  if [ -z $REMOTE_APP ]; then
    stop_spinner
    echo "Error: Environment variable of 'REMOTE_APP' not found."

    if [ $is_scan_initial_run -eq 0 ]; then
      state="cancel"
      exit 1
    fi
  else
    stop_spinner
  fi

  if ! which adb >/dev/null; then
    if [ $is_scan_initial_run -eq 0 ]; then

      stop_spinner
      echo "Warning: Adb command not found, please install android platform-tools, skip adb? (y/n)"
      read answer
      if [ "$answer" == "y" ]; then
        echo "Adb skipped"
        is_adb_skipped=1
      elif [ "$answer" == "n" ]; then
        state="cancel"
        exit 1
      else
        echo "Input not valid"
        check_initial_run
      fi
    else
      stop_spinner
      echo "Warning: Adb command not found, you cannot run and launch apk without adb installed."
      exit 1
    fi
  else
    stop_spinner
    assign_apk_and_package_name
  fi

  remote_home=$(gcloud_ssh $REMOTE_VM pwd)
  remote_parent_directory="$remote_home/remote/"
  if gcloud_ssh $REMOTE_VM "[ -d $remote_parent_directory ]"; then
    is_has_parent=1
  else
    is_has_parent=0
  fi
}

function assign_apk_and_package_name() {
  case $REMOTE_APP in
  "salam")
    PACKAGE_NAME="com.graveltechnology.oui"
    ;;
  "owner")
    PACKAGE_NAME="com.graveltechnology.owner"
    ;;
  "kernet")
    PACKAGE_NAME="com.graveltechnology.kernet"
    ;;
  *)
    PACKAGE_NAME=""
    ;;
  esac

  case $BUILD_TYPE in
  "Debug")
    APK_NAME="$REMOTE_APP-debug.apk"
    APK_DIR="$CURRENT_DIR/apps/$REMOTE_APP/build/outputs/apk/debug"
    PACKAGE_NAME+=".debug"
    ;;
  "Alpha")
    APK_DIR="$CURRENT_DIR/apps/$REMOTE_APP/build/outputs/apk/alpha"
    APK_NAME="$REMOTE_APP-alpha.apk"
    PACKAGE_NAME+=".alpha"
    ;;
  "Release")
    APK_DIR="$CURRENT_DIR/apps/$REMOTE_APP/build/outputs/apk/release"
    APK_NAME="$REMOTE_APP-release.apk"
    ;;
  esac
}

function install_apk() {
  if [ $is_adb_skipped -eq 0 ]; then
    adb install "$APK_DIR/$APK_NAME"
  fi
}

function replace_apk() {
  if [ $is_adb_skipped -eq 0 ]; then
    adb uninstall $PACKAGE_NAME
    adb install "$APK_DIR/$APK_NAME"
  fi
}

function launch_apk() {
  if [ $is_adb_skipped -eq 0 ]; then
    launcher=$(adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER $PACKAGE_NAME)
    activity_launcher=$(echo "$launcher" | sed -n 2p)
    adb shell am start -n $activity_launcher
  fi
}

main "$@"
exit
