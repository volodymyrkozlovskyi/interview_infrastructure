#This simple AWS infrastructure as code created with Terraform and made for DevOps position interview.

##How to use:
  1) pull/download this repository to your computer
  2) change variables:
      - region                  = set the AWS region that you want use to build infrastructure
      - vpc_cidr                = to set cidr block for your networking
      - public_subnet_cidrs     = set the cidr for your public subnets and their quantity
      - private_subnet_cidrs    = set the cidr for your public subnets and their quantity
      - key                     = name of your ssh key for connection to instances
      - instance_volume_size_gb = size of hard drive for instances in GB
  3) export your AWS_SECRET_ACCESS_KEY and AWS_ACCESS_KEY_ID
  4) run terraform init
  5) terraform plan to see if there are no errors and see how many resources will be created
  6) terraform apply

By default, this code will create an infrastructure of:
  - 1 VPC
  - 2 public and 2 private subnets
  - internet gateway
  - NAT gateway with Elastic IP for each public subnet
  - routes and association for public subnets to the internet gateway
  - routes and association for private subnets to NAT
  - 3 security groups for bastion host, web app, and load balancer
  - launch configuration for bastion host and application server
  - autoscaling group for bastion host and application server (minimum 1, maximum 1)
  - elastic load balancer (application) will be placed in public subnets listen for HTTP over port 80 and forward to the application server in a private subnet

There is a user_data script for the application server. I made it just to speed up the process of application deployment
it will install system updates, docker, and docker-compose.
Then pulling the repository from git hub with the application (https://github.com/volodymyrkozlovskyi/to_do.git),
exports environment variables needed for application to work.
At the end of the script, it runs the commands docker-compose -f docker-compose-deploy.yml up --build -d and docker-compose -f docker-compose-deploy.yml run app python manage.py migrate
to build and run the containers and migrate database schema for the freshly installed app.
