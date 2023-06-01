#!/bin/bash
set -e

function install_gcloud() {
  brew install --cask google-cloud-sdk
}

function login_gcloud() {
  read -p "You must logged in google cloud with Gravel Account (y/n)? " choice

  if [[ "$choice" == "y" ]]; then
    gcloud auth login
  elif [[ "$choice" == "n" ]]; then
    echo "You must logged in"
    login_gcloud
  else
    echo "Option not valid"
    login_gcloud
  fi

  gcloud config set project gravel-technology
}

function verify_homebrew() {
  if ! command -v brew &>/dev/null; then
    echo "> Homebrew not installed. Please install Homebrew, see https://brew.sh/"
    exit 1
  fi
}

function install_remotesh() {
  content_remotesh=$(curl --request GET --header 'PRIVATE-TOKEN: bx_xHHKxFUGniHfrxsdr' 'https://gitlab.graveltechnology.com/api/v4/projects/237/repository/files/scripts%2Fremote.sh/blame?ref=main')
  echo $content_remotesh
}

function main() {
  verify_homebrew
  install_gcloud
  if gcloud auth list | grep -q "ACTIVE"; then
    email=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    echo "Google cloud logged in with $email"
  else
    login_gcloud
  fi

  install_remotesh
}

main "$@"
exit
