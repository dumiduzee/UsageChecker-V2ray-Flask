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

# Install necessary packages
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv lsof curl unzip supervisor

# Define the URL of the repository or zip file containing the Flask app
REPO_URL="https://github.com/dumiduzee/newTester/archive/refs/tags/v0.2.zip"

APP_DIR="flask_app"

# Create the directory for the Flask app files
mkdir -p $APP_DIR

# Download and unzip the Flask app files into the directory
wget $REPO_URL -O $APP_DIR/flask_app.zip
unzip $APP_DIR/flask_app.zip -d $APP_DIR
rm $APP_DIR/flask_app.zip

# Navigate to the correct directory
cd $APP_DIR/newTester-0.2  # Adjust according to the structure of the extracted files

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

echo "Flask app has been installed and is running. You can access it at http://$VPS_IP:$PORT"
