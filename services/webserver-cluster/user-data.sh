#!/bin/bash
mkdir -p /home/ec2-user
cat > /home/ec2-user/index.html <<EOT
<h1>Hello from AL2023</h1>
<p>DB address: ${db_address}</p>
<p>DB port: ${db_port}</p>
EOT

nohup python3 -m http.server ${server_port} --directory /home/ec2-user &