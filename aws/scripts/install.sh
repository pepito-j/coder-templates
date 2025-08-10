#!/bin/bash

apt install -y nginx jq
snap install aws-cli --classic # Installs AWS v2

CODER_VERSION=$(aws ssm get-parameter --name CODER_VERSION --output json | jq -r ".Parameter.Value")
CODER_ACCESS_URL=$(aws ssm get-parameter --name CODER_ACCESS_URL --output json | jq -r ".Parameter.Value")
CODER_WILDCARD_ACCESS_URL=$(aws ssm get-parameter --name CODER_WILDCARD_ACCESS_URL --output json | jq -r ".Parameter.Value")
CODER_HTTP_ADDRESS=$(aws ssm get-parameter --name CODER_HTTP_ADDRESS --output json | jq -r ".Parameter.Value")
CODER_TLS_ADDRESS=$(aws ssm get-parameter --name CODER_TLS_ADDRESS --output json | jq -r ".Parameter.Value")
CODER_TLS_ENABLE=$(aws ssm get-parameter --name CODER_TLS_ENABLE --output json | jq -r ".Parameter.Value")

CODER_ACCESS_URL_TRIMMED=$${CODER_ACCESS_URL#"http://"}
CODER_ACCESS_URL_TRIMMED=$${CODER_ACCESS_URL_TRIMMED#"https://"}

su 'ubuntu' -l -c "

wget -O - https://coder.com/install.sh | sh -s -- --version=$CODER_VERSION

sudo tee /etc/nginx/sites-available/default <<-'EOF'
server {
    server_name $CODER_ACCESS_URL_TRIMMED $CODER_WILDCARD_ACCESS_URL;

    # HTTP configuration
    listen 80;
    listen [::]:80;

    location / {
        proxy_pass  http://$CODER_HTTP_ADDRESS;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
        add_header Strict-Transport-Security \"max-age=15552000; includeSubDomains\" always;
    }
}
EOF

tee /home/ubuntu/coder.conf <<-EOF
CODER_ACCESS_URL=$CODER_ACCESS_URL
CODER_WILDCARD_ACCESS_URL=$CODER_WILDCARD_ACCESS_URL
CODER_HTTP_ADDRESS=$CODER_HTTP_ADDRESS
CODER_TLS_ADDRESS=$CODER_TLS_ADDRESS
CODER_TLS_ENABLE=$CODER_TLS_ENABLE
EOF

tee /home/ubuntu/coder.service <<-EOF
[Unit]
Description=Coder Service

[Service]
Type=simple
EnvironmentFile=/home/ubuntu/coder.conf
User=ubuntu
ExecStart=/usr/bin/env coder server

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable /home/ubuntu/coder.service

sudo systemctl daemon-reload
sudo systemctl enable --now coder
sudo systemctl restart coder.service
sudo systemctl restart nginx.service
"