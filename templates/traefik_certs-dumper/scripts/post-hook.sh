#!/bin/bash
set -euo pipefail
exec 1> >(stdbuf -oL cat) 2>&1

#--------------------
# DEPENDENCY CHECK
#--------------------

install_openssh() {
  if ! command -v scp >/dev/null; then
    echo "[INFO] Installing openssh-client..."
    apk add --quiet --no-cache openssh-client
  fi
}

#--------------------
# CERTIFICATE COPY FUNCTION
#--------------------

copy_certificates() {
  local src_cert="$1"
  local src_key="$2"
  local dest_host="$3"
  local dest_user="$4"
  local dest_cert_path="$5"
  local dest_key_path="$6"
  local ssh_key="$7"

  echo "[INFO] Copying certs to ${dest_user}@${dest_host}..."

  scp -i "$ssh_key" -o StrictHostKeyChecking=accept-new "$src_cert" "${dest_user}@${dest_host}:$dest_cert_path"
  scp -i "$ssh_key" "$src_key" "${dest_user}@${dest_host}:$dest_key_path"
}

#--------------------
# REMOTE SERVICE RESTART FUNCTION
#--------------------

restart_remote_docker_compose() {
  local dest_host="$1"
  local dest_user="$2"
  local remote_project_path="$3"
  local ssh_key="$4"

  echo "[INFO] Restarting Docker Compose at ${remote_project_path} on ${dest_host}..."
  ssh -i "$ssh_key" "${dest_user}@${dest_host}" "cd ${remote_project_path} && docker compose restart"
}

#--------------------
# EXAMPLE USAGE
#--------------------

mailcow() {
  local ssh_key="/root/.ssh/id_rsa"
  local dest_host="192.168.20.120"
  local dest_user="root"
  local project_path="/opt/mailcow-dockerized"
  local local_cert="/data/files/mailcow.prd.xn--lb-1ia.de/certificate.pem"
  local local_key="/data/files/mailcow.prd.xn--lb-1ia.de/privatekey.pem"
  local remote_cert="${project_path}/data/assets/ssl/cert.pem"
  local remote_key="${project_path}/data/assets/ssl/key.pem"

  copy_certificates "$local_cert" "$local_key" "$dest_host" "$dest_user" "$remote_cert" "$remote_key" "$ssh_key"
  restart_remote_docker_compose "$dest_host" "$dest_user" "$project_path" "$ssh_key"
}

example_other_service() {
  local ssh_key="/root/.ssh/id_rsa"
  local dest_host="192.168.20.121"
  local dest_user="root"
  local project_path="/opt/other-service"
  local local_cert="/data/files/other.domain.tld/certificate.pem"
  local local_key="/data/files/other.domain.tld/privatekey.pem"
  local remote_cert="${project_path}/certs/cert.pem"
  local remote_key="${project_path}/certs/key.pem"

  copy_certificates "$local_cert" "$local_key" "$dest_host" "$dest_user" "$remote_cert" "$remote_key" "$ssh_key"
  restart_remote_docker_compose "$dest_host" "$dest_user" "$project_path" "$ssh_key"
}

#--------------------
# MAIN
#--------------------

install_openssh
mailcow
echo "[INFO] Done."