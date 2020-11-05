#!/bin/bash
sudo yum update -y
sudo yum install git -y
sudo amazon-linux-extras install docker
sudo systemctl start docker
sudo usermod -a -G docker ec2-user
sudo systemctl enable docker
sudo curl -L https://github.com/docker/compose/releases/download/1.21.0/docker-compose-`uname -s`-`uname -m` | sudo tee /usr/local/bin/docker-compose > /dev/null
sudo chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
cd /home/ec2-user/
git clone https://github.com/volodymyrkozlovskyi/to_do.git
cd to_do
sudo export $(grep -v '^#' .env | xargs)
sudo docker-compose -f docker-compose-deploy.yml up --build -d
sleep 60
sudo docker-compose -f docker-compose-deploy.yml run app python manage.py migrate
