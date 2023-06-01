#! /bin/sh
host="$1"
shift
exec gcloud compute ssh --zone asia-southeast2-a --internal-ip "$host" -- "$@"
