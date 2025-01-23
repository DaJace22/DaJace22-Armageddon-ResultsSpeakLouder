variable "vpc_availability_zone_HK" {
  type        = list(string)
  description = "Availability Zone"
  default     = ["ap-east-1a", "ap-east-1c"]
}

// VPC
resource "aws_vpc" "hong_kong" {
  cidr_block           = "10.76.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  provider             = aws.hong_kong
  tags = {
    Name = "Hong Kong VPC"
  }
}

// Subnets
resource "aws_subnet" "public_subnet_HK" {
  vpc_id            = aws_vpc.hong_kong.id
  count             = length(var.vpc_availability_zone_HK)
  cidr_block        = cidrsubnet(aws_vpc.hong_kong.cidr_block, 8, count.index + 1)
  availability_zone = element(var.vpc_availability_zone_HK, count.index)
  provider          = aws.hong_kong
  tags = {
    Name = "Hong Kong Public Subnet${count.index + 1}",
  }
}

resource "aws_subnet" "private_subnet_HK" {
  vpc_id            = aws_vpc.hong_kong.id
  count             = length(var.vpc_availability_zone_HK)
  cidr_block        = cidrsubnet(aws_vpc.hong_kong.cidr_block, 8, count.index + 11)
  availability_zone = element(var.vpc_availability_zone_HK, count.index)
  provider          = aws.hong_kong
  tags = {
    Name = "Hong Kong Private Subnet${count.index + 1}",
  }
}

// IGW
resource "aws_internet_gateway" "hong_kong_igw" {
  vpc_id   = aws_vpc.hong_kong.id
  provider = aws.hong_kong

  tags = {
    Name = "hong_kong_igw"
  }
}

// RT for the public subnet
resource "aws_route_table" "hong_kong_route_table_public_subnet" {
  vpc_id   = aws_vpc.hong_kong.id
  provider = aws.hong_kong

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hong_kong_igw.id
  }

  tags = {
    Name = "Route Table for Public Subnet",
  }

}

// Association between RT and IG
resource "aws_route_table_association" "hong_kong_public_subnet_association" {
  route_table_id = aws_route_table.hong_kong_route_table_public_subnet.id
  count          = length((var.vpc_availability_zone_HK))
  subnet_id      = element(aws_subnet.public_subnet_HK[*].id, count.index)
  provider       = aws.hong_kong
}

// EIP
resource "aws_eip" "hong_kong_eip" {
  domain   = "vpc"
  provider = aws.hong_kong
}

// NAT
resource "aws_nat_gateway" "hong_kong_nat" {
  allocation_id = aws_eip.hong_kong_eip.id
  subnet_id     = aws_subnet.public_subnet_HK[0].id
  provider      = aws.hong_kong
}

// RT for private Subnet
resource "aws_route_table" "hong_kong_route_table_private_subnet" {
  vpc_id   = aws_vpc.hong_kong.id
  provider = aws.hong_kong

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.hong_kong_nat.id
  }

  route {
    cidr_block         = "10.70.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.local_hong_kong.id
  }

  tags = {
    Name = "Route Table for Private Subnet",
  }

}

// RT Association Private
resource "aws_route_table_association" "hong_kong_private_subnet_association" {
  route_table_id = aws_route_table.hong_kong_route_table_private_subnet.id
  count          = length((var.vpc_availability_zone_HK))
  subnet_id      = element(aws_subnet.private_subnet_HK[*].id, count.index)
  provider       = aws.hong_kong
}

// Security Groups
resource "aws_security_group" "hong_kong_alb_sg" {
  name        = "hong_kong-alb-sg"
  description = "Security Group for Application Load Balancer"
  provider    = aws.hong_kong

  vpc_id = aws_vpc.hong_kong.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "hong_kong-alb-sg"
  }
}

// Security Group For EC2
resource "aws_security_group" "hong_kong_ec2_sg" {
  name        = "hong_kong-ec2-sg"
  description = "Security Group for Webserver Instance"
  provider    = aws.hong_kong

  vpc_id = aws_vpc.hong_kong.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "TCP"
    security_groups = [aws_security_group.hong_kong_alb_sg.id]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "hong_kong-ec2-sg"
  }
}

// Load Balancer
resource "aws_lb" "hong_kong_alb" {
  name                       = "hong_kong-load-balancer"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = aws_subnet.public_subnet_HK[*].id
  depends_on                 = [aws_internet_gateway.hong_kong_igw]
  enable_deletion_protection = false
  provider                   = aws.hong_kong

  tags = {
    Name    = "hong_kongLoadBalancer"
    Service = "hong_kong"
  }
}

// Target Group
resource "aws_lb_target_group" "hong_kong-tg" {
  name        = "hong_kong-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.hong_kong.id
  provider    = aws.hong_kong
  target_type = "instance"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200"
  }

  tags = {
    Name    = "hong_kong-tg"
    Service = "hong_kongTG"
  }
}

// Listener
resource "aws_lb_listener" "hong_kong_http" {
  load_balancer_arn = aws_lb.hong_kong_alb.arn
  port              = 80
  protocol          = "HTTP"
  provider          = aws.hong_kong

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.hong_kong-tg.arn
  }
}

// Launch Template
resource "aws_launch_template" "hong_kong_LT" {
  provider      = aws.hong_kong
  name          = "hong_kong_LT"
  image_id      = "ami-08d17dd56120aa5b4"
  instance_type = "t3.micro"

    user_data = filebase64("userdata.sh")

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.hong_kong_ec2_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "hong_kong-ec2-web-server"
    }
  }
}

// Auto Scaling Group
resource "aws_autoscaling_group" "hong_kong_ec2_asg" {
  max_size            = 3
  min_size            = 2
  desired_capacity    = 2
  name                = "hong_kong-web-server-asg"
  target_group_arns   = [aws_lb_target_group.hong_kong-tg.arn]
  vpc_zone_identifier = aws_subnet.private_subnet_HK[*].id
  provider            = aws.hong_kong

  launch_template {
    id      = aws_launch_template.hong_kong_LT.id
    version = "$Latest"
  }

  health_check_type = "EC2"

