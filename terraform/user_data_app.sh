#!/bin/bash -xe
# Cloud-init for a single-environment host (prod or staging)

# These three placeholders are replaced by Terraform templatefile()
ENV_NAME="${ENV_NAME}"
DOMAIN="${DOMAIN}"             # may be empty; we default server_name to _
REPO_URL="${GIT_REPO_URL}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release git nginx

# Ensure nginx is enabled early
systemctl enable --now nginx

# Docker + Compose
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

# App directory
mkdir -p /opt/hello-svc
cd /opt/hello-svc

# Clone your repo if not present
if [ ! -d "/opt/hello-svc/.git" ]; then
  git clone "$REPO_URL" .
fi

# Compose file: single service; your app listens on container port 8080
# NOTE: this heredoc is quoted, so the shell won't expand $... here. Terraform will replace ${ENV_NAME}.
cat >/opt/hello-svc/docker-compose.yml <<'YAML'
version: "3.9"
services:
  app:
    build: .
    container_name: hello-app
    environment:
      - ENV=${ENV_NAME}
    ports:
      - "127.0.0.1:8080:8080"
    restart: always
YAML

# Build & run
docker compose build
docker compose up -d

# Self-signed TLS (valid 365 days)
mkdir -p /etc/nginx/ssl/app
CN_VAL="$DOMAIN"
if [ -z "$CN_VAL" ]; then CN_VAL="localhost"; fi

openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout /etc/nginx/ssl/app/privkey.pem \
  -out    /etc/nginx/ssl/app/fullchain.pem \
  -subj "/CN=$CN_VAL"

chmod 600 /etc/nginx/ssl/app/privkey.pem

# Nginx vhost (default server if DOMAIN empty)
SERVER_NAME_LINE="server_name $DOMAIN;"
if [ -z "$DOMAIN" ]; then SERVER_NAME_LINE="server_name _;"; fi

# Write vhost with root redirect to /hello and proxy to the app
# This heredoc is unquoted so the shell expands $SERVER_NAME_LINE,
# while \$host etc remain literal for Nginx.
cat >/etc/nginx/sites-available/hello.conf <<NGINX
# HTTP -> HTTPS
server {
    listen 80 default_server;
    $SERVER_NAME_LINE
    return 301 https://\$host\$request_uri;
}

# HTTPS
server {
    listen 443 ssl http2 default_server;
    $SERVER_NAME_LINE

    ssl_certificate     /etc/nginx/ssl/app/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/app/privkey.pem;

    access_log /var/log/nginx/hello.access.log;
    error_log  /var/log/nginx/hello.error.log;

    # Redirect only root (/) to the app's handler path
    location = / {
        return 302 /hello;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX

# Enable our site and ensure the default site is disabled so it can't shadow us
ln -sf /etc/nginx/sites-available/hello.conf /etc/nginx/sites-enabled/hello.conf
rm -f /etc/nginx/sites-enabled/default

# Validate and reload nginx
nginx -t
systemctl reload nginx