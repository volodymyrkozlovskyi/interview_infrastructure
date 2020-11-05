#-===============================================General Info====================================================
provider "aws" {
  region = "us-east-1"
}


variable "vpc_cidr" {
  default = "172.16.0.0/16"
}

variable "public_subnet_cidrs" {
  default = [
    "172.16.1.0/24",
    "172.16.2.0/24"
  ]
}

variable "private_subnet_cidrs" {
  default = [
    "172.16.11.0/24",
    "172.16.22.0/24"
  ]
}

variable "key" {
  default = "int-key"
}

variable "descr_tag" {
  default = "created_for_civis_interview"
}

variable "instance_volume_size_gb" {
  description = "The root volume size, in gigabytes"
  default     = "8"
}

data "aws_availability_zones" "available" {

}

data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

#================================================Network infrastructure==========================================

resource "aws_vpc" "civis_interview" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "madecivis_interview"
  }
}

resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.civis_interview.id
  tags = {
    description = "${var.descr_tag}"
  }
}

resource "aws_eip" "nat_eip" {
  # Elastic IP for my NAT GW
  count = length(aws_subnet.public_subnets[*].id)
}

resource "aws_nat_gateway" "nat_gw" {
  count         = length(aws_subnet.public_subnets[*].id)
  allocation_id = element(aws_eip.nat_eip[*].id, count.index)
  subnet_id     = element(aws_subnet.public_subnets[*].id, count.index)
  tags = {
    description = "${var.descr_tag}"
  }
}

## subnets----------------------------------------------------------------------

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.civis_interview.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.civis_interview.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "private-${count.index + 1}"
    description = "${var.descr_tag}"
  }
}

## routes-----------------------------------------------------------------------

resource "aws_route_table" "public_subnets" {
  vpc_id = aws_vpc.civis_interview.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW.id
  }
  tags = {
    Name        = "public_subnet-route"
    description = "${var.descr_tag}"
  }
}

resource "aws_route_table" "private_subnets" {
  count  = length(aws_nat_gateway.nat_gw)
  vpc_id = aws_vpc.civis_interview.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = element(aws_nat_gateway.nat_gw[*].id, count.index)
  }
  tags = {
    Name        = "private_subnet-route"
    description = "${var.descr_tag}"
  }
}

resource "aws_route_table_association" "public_routes" {
  count          = length(aws_subnet.public_subnets[*].id)
  route_table_id = aws_route_table.public_subnets.id
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
}

resource "aws_route_table_association" "private_routes" {
  count          = length(aws_subnet.private_subnets[*].id)
  route_table_id = aws_route_table.private_subnets[count.index].id
  subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
}

##security_groups---------------------------------------------------------------
#-bastion
resource "aws_security_group" "bastion_ssh_sc" {
  name   = "bastion_ssh_sc"
  vpc_id = aws_vpc.civis_interview.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#-docker server security group
resource "aws_security_group" "app_sc" {
  name   = "app_srv_sc"
  vpc_id = aws_vpc.civis_interview.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_sc" {
  name   = "loadbalancer_web_sc"
  vpc_id = aws_vpc.civis_interview.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
##autoscaling-------------------------------------------------------------------
#bastion
resource "aws_launch_configuration" "bastion_lc" {
  name          = "bastion_lc"
  image_id      = "${data.aws_ami.latest_amazon_linux.id}"
  instance_type = "t2.micro"
  #  user_data       = file("bastion.sh") -------------------- this script was used to copy ssh key for faster troubleshooting and testing
  security_groups = [aws_security_group.bastion_ssh_sc.id, ]
  key_name        = var.key

  root_block_device {
    volume_size = var.instance_volume_size_gb
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "bastion_as" {
  name                 = "bastion_as"
  launch_configuration = "${aws_launch_configuration.bastion_lc.name}"
  min_size             = 1
  max_size             = 1
  vpc_zone_identifier  = flatten(aws_subnet.public_subnets[*].id)

  lifecycle {
    create_before_destroy = true
  }
}
#docker server
resource "aws_launch_configuration" "app_srv_lc" {
  name            = "app_srv_lc"
  image_id        = "${data.aws_ami.latest_amazon_linux.id}"
  instance_type   = "t2.micro"
  user_data       = file("user_data_app.sh")
  security_groups = [aws_security_group.app_sc.id, ]
  key_name        = var.key

  root_block_device {
    volume_size = var.instance_volume_size_gb
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app_srv_as" {
  name                 = "app_srv_as"
  launch_configuration = "${aws_launch_configuration.app_srv_lc.name}"
  min_size             = 1
  max_size             = 1
  vpc_zone_identifier  = [aws_subnet.private_subnets[0].id]
  target_group_arns    = [aws_lb_target_group.app_web_rg.arn]

  lifecycle {
    create_before_destroy = true
  }
}
#-----------------------------------ELB---------------------------------------------------------
resource "aws_lb" "app_web_lb" {
  name               = "load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.web_sc.id}"]
  subnets            = flatten(aws_subnet.public_subnets[*].id)
}

resource "aws_lb_target_group" "app_web_rg" {
  name     = "app-targets"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.civis_interview.id}"
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 15
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = "${aws_lb.app_web_lb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.app_web_rg.arn}"
  }
}
