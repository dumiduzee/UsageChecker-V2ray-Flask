#!/bin/bash
cur_dir=$(pwd)

# Function to check if a port is in use
is_port_in_use() {
  sudo lsof -i -P -n | grep ":$1 " > /dev/null
  return $?
}

# Function to check if the input is a valid port number
is_valid_port() {
  [[ $1 =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# Prompt the user for the port number
while true; do
  read -p "Enter the port number [Must be not busy]: " PORT

  if ! is_valid_port "$PORT"; then
    echo "Invalid port number. Please enter a number between 1 and 65535."
  elif is_port_in_use "$PORT"; then
    echo "Port $PORT is already in use by another program. Please choose a different port."
  else
    break
  fi
done

print_color() {
    local color_code="$1"
    shift
    echo -e "\e[${color_code}m$@\e[0m"
}
print_color "32" "Installing jq..."
sudo apt-get install -y jq > /dev/null 2>&1
print_color "32" "jq installed successfully!"

read -p "Enter the Cloudflare API key: " CF_API_KEY
read -p "Enter the Cloudflare email: " CF_EMAIL
read -p "Enter the domain name (e.g., example.com): " DOMAIN
read -p "Enter the subdomain to create (e.g., sub.example.com): " SUBDOMAIN
VPS_IP=$(curl -s ifconfig.me)
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
    -H "X-Auth-Email: $CF_EMAIL" \
    -H "X-Auth-Key: $CF_API_KEY" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')
if [[ -z "$ZONE_ID" ]]; then
    print_color "31" "Error: Failed to retrieve Zone ID. Please check your domain name. Exiting."
    exit 1
fi
print_color "34" "Domain: $DOMAIN"
print_color "34" "Zone ID: $ZONE_ID"
RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "X-Auth-Email: $CF_EMAIL" \
    -H "X-Auth-Key: $CF_API_KEY" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$SUBDOMAIN\",\"content\":\"$VPS_IP\",\"ttl\":1,\"proxied\":false}")

if [[ "$RESPONSE" == *'"success":true'* ]]; then
    print_color "32" "Subdomain $SUBDOMAIN created successfully with TTL set to Auto."
else
    print_color "31" "Failed to create subdomain. Response from Cloudflare: $RESPONSE"
fi

# Install necessary packages
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv lsof curl unzip supervisor

# Define the URL of the repository or zip file containing the Flask app
REPO_URL="https://github.com/dumiduzee/UsageChecker-V2ray-Flask/archive/refs/tags/v0.3.zip"

APP_DIR="flask_app"

# Create the directory for the Flask app files
mkdir -p $APP_DIR

# Download and unzip the Flask app files into the directory
wget $REPO_URL -O $APP_DIR/flask_app.zip
unzip $APP_DIR/flask_app.zip -d $APP_DIR
rm $APP_DIR/flask_app.zip

# Navigate to the correct directory
cd $APP_DIR/UsageChecker-V2ray-Flask-0.3  # Adjust according to the structure of the extracted files

# Create and activate a virtual environment
python3 -m venv venv
source venv/bin/activate

# Install the required Python packages
pip install -r requirements.txt
pip install gunicorn  # Install Gunicorn

# Update the app.py file with the user-provided port
sed -i "s/5000/$PORT/" app.py

# Create Supervisor configuration file for the Flask app
sudo tee /etc/supervisor/conf.d/flaskapp.conf > /dev/null <<EOL
[program:flaskapp]
command=$(pwd)/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:$PORT app:app
directory=$(pwd)
user=$USER
autostart=true
autorestart=true
stdout_logfile=/var/log/flaskapp.log
stderr_logfile=/var/log/flaskapp.err.log
EOL

# Update Supervisor and start the Flask app
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start flaskapp

# Get the VPS IP address
VPS_IP=$(curl -s ifconfig.me)

echo "Flask app has been installed and is running. You can access it at http://$SUBDOMAIN:$PORT"
