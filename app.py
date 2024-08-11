from flask import Flask, render_template
import sqlite3
from datetime import datetime
import pytz
import os

app = Flask(__name__)

DATABASE = '/etc/x-ui/x-ui.db'

def get_db_connection():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

def bytes_to_gb(bytes_value):
    return bytes_value / (1024 ** 3)  # Convert bytes to gigabytes

def convert_timestamp(timestamp, timezone='Asia/Colombo'):
    # Convert timestamp from milliseconds to seconds
    timestamp = int(timestamp) / 1000
    local_time = datetime.fromtimestamp(timestamp)
    local_time = local_time.astimezone(pytz.timezone(timezone))
    return local_time.strftime('%Y-%m-%d %H:%M:%S')

@app.route('/', methods=['GET'])
def home():
    return render_template('home.html')

@app.route('/<username>', methods=['GET'])
def index(username):
    data = None
    if username:
        try:
            conn = get_db_connection()
            cursor = conn.cursor()
            # Normalize the username to lowercase
            normalized_username = username.strip().lower()

            # Query for case-insensitive match and fetch expire_time
            cursor.execute('SELECT email, total, up, down, expiry_time, enable FROM client_traffics WHERE LOWER(email) = ?', (normalized_username,))
            data = cursor.fetchone()
            conn.close()
            
            if data:
                data = dict(data)
                data['used'] = data['up'] + data['down']
                data['used_gb'] = bytes_to_gb(data['used'])
                data['upload_gb'] = bytes_to_gb(data['up'])
                data['download_gb'] = bytes_to_gb(data['down'])
                data['total_gb'] = bytes_to_gb(data['total'])
                
                if data['total'] == 0:
                    data['display'] = 'Unlimited Bandwidth'
                    data['percentage'] = None  # No percentage to calculate
                    data['remaining'] = None
                else:
                    data['display'] = f'{data["used_gb"]:.2f} GB / {data["total_gb"]:.2f} GB'
                    data['percentage'] = (data['used_gb'] / data['total_gb']) * 100
                    remaining_value = max(data['total_gb'] - data['used_gb'], 0)
                    data['remaining'] = f"{round(remaining_value, 2)} GB"

                data['upload_download'] = f'{data["upload_gb"]:.2f} GB / {data["download_gb"]:.2f} GB'
                
                # Add expire_time to the data
                data['calculated_expiry_time'] = convert_timestamp(data['expiry_time'], 'Asia/Colombo')

                if data['expiry_time'] == 0:
                    data['expiry_time_display'] = 'Never Expire'
                    data['expiry_status'] = 'valid'
                else:
                    current_time = datetime.now(pytz.timezone('Asia/Colombo'))
                    expiry_time = datetime.fromtimestamp(int(data['expiry_time']) / 1000, tz=pytz.timezone('Asia/Colombo'))
                    if current_time > expiry_time:
                        data['expiry_time_display'] = data['calculated_expiry_time']
                        data['expiry_status'] = 'expired'
                    else:
                        data['expiry_time_display'] = data['calculated_expiry_time']
                        data['expiry_status'] = 'valid'

                if data['enable'] == 0:
                    data['status'] = 'config offline'
                    data['contact_user'] = 'contact admin for renew your config: '
                    data['admin_link1'] = 'https://t.me/knowunknownknow'
                else:
                    data['status'] = 'config online'

            else:
                data = {'error': 'No data found for the provided username.'}

        except sqlite3.DatabaseError as e:
            data = {'error': f'Database error: {e}'}
    
    return render_template('index.html', data=data, username=username)

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 5000))
    app.run(host='0.0.0.0', port=port, debug=True)
