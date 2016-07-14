#! /bin/bash
#run as sudo

set +e

echo "Install & setup Xvfb"
apt-get install -y xvfb

echo "Install & setup Chrome"
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/google-chrome-stable_current_amd64.deb
dpkg -i /tmp/google-chrome-stable_current_amd64.deb
apt-get install -f -y

echo "Install Chromedriver 2.21"
wget -q -O /tmp/chromedriver.zip http://chromedriver.storage.googleapis.com/2.22/chromedriver_linux64.zip && unzip /tmp/chromedriver.zip chromedriver -d /usr/local/bin/;
chmod 751 /usr/local/bin/chromedriver

echo "Add Xvfb as service & run"
cat <<EOF > /etc/systemd/system/xvfb.service
[Unit]
Description=X Virtual Frame Buffer Service
After=network.target

[Service]
ExecStart=/usr/bin/Xvfb :1 -screen 0 1024x768x24

[Install]
WantedBy=multi-user.target
EOF
systemctl enable /etc/systemd/system/xvfb.service