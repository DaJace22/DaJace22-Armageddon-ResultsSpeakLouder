variable "vpc_availability_zone_NY" {
  type        = list(string)
  description = "Availability Zone"
  default     = ["us-east-1a", "us-east-1b"]
}

// VPC
resource "aws_vpc" "new_york" {
  cidr_block           = "10.72.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  provider             = aws.new_york
  tags = {
    Name = "New York VPC"
  }
}

// Subnets
resource "aws_subnet" "public_subnet_NY" {
  vpc_id            = aws_vpc.new_york.id
  count             = length(var.vpc_availability_zone_NY)
  cidr_block        = cidrsubnet(aws_vpc.new_york.cidr_block, 8, count.index + 1)
  availability_zone = element(var.vpc_availability_zone_NY, count.index)
  provider          = aws.new_york
  tags = {
    Name = "New York Public Subnet${count.index + 1}",
  }
}

resource "aws_subnet" "private_subnet_NY" {
  vpc_id            = aws_vpc.new_york.id
  count             = length(var.vpc_availability_zone_NY)
  cidr_block        = cidrsubnet(aws_vpc.new_york.cidr_block, 8, count.index + 11)
  availability_zone = element(var.vpc_availability_zone_NY, count.index)
  provider          = aws.new_york
  tags = {
    Name = "New York Private Subnet${count.index + 1}",
  }
}

// IGW
resource "aws_internet_gateway" "newyork_igw" {
  vpc_id   = aws_vpc.new_york.id
  provider = aws.new_york

  tags = {
    Name = "newyork_igw"
  }
}

// RT for the public subnet
resource "aws_route_table" "new_york_route_table_public_subnet" {
  vpc_id   = aws_vpc.new_york.id
  provider = aws.new_york

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.newyork_igw.id
  }

  tags = {
    Name = "Route Table for Public Subnet",
  }

}

// Association between RT and IG
resource "aws_route_table_association" "new_york_public_subnet_association" {
  route_table_id = aws_route_table.new_york_route_table_public_subnet.id
  count          = length((var.vpc_availability_zone_NY))
  subnet_id      = element(aws_subnet.public_subnet_NY[*].id, count.index)
  provider       = aws.new_york
}

// EIP
resource "aws_eip" "new_york_eip" {
  domain   = "vpc"
  provider = aws.new_york
}

// NAT
resource "aws_nat_gateway" "new_york_nat" {
  allocation_id = aws_eip.new_york_eip.id
  subnet_id     = aws_subnet.public_subnet_NY[0].id
  provider      = aws.new_york
}

// RT for private Subnet
resource "aws_route_table" "new_york_route_table_private_subnet" {
  vpc_id   = aws_vpc.new_york.id
  provider = aws.new_york

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.new_york_nat.id
  }

  route {
    cidr_block         = "10.70.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.local_new_york.id
  }

  tags = {
    Name = "Route Table for Private Subnet",
  }

}

// RT Association Private
resource "aws_route_table_association" "new_york_private_subnet_association" {
  route_table_id = aws_route_table.new_york_route_table_private_subnet.id
  count          = length((var.vpc_availability_zone_NY))
  subnet_id      = element(aws_subnet.private_subnet_NY[*].id, count.index)
  provider       = aws.new_york
}

// Security Groups
resource "aws_security_group" "new_york_alb_sg" {
  name        = "new_york-alb-sg"
  description = "Security Group for Application Load Balancer"
  provider    = aws.new_york

  vpc_id = aws_vpc.new_york.id

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
    Name = "new_york-alb-sg"
  }
}

// Security Group For EC2
resource "aws_security_group" "new_york_ec2_sg" {
  name        = "new_york-ec2-sg"
  description = "Security Group for Webserver Instance"
  provider    = aws.new_york

  vpc_id = aws_vpc.new_york.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "TCP"
    security_groups = [aws_security_group.new_york_alb_sg.id]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "new_york-ec2-sg"
  }
}

// Load Balancer
resource "aws_lb" "newyork_alb" {
  name                       = "newyork-load-balancer"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = aws_subnet.public_subnet_NY[*].id
  depends_on                 = [aws_internet_gateway.newyork_igw]
  enable_deletion_protection = false
  provider                   = aws.new_york

  tags = {
    Name    = "newyorkLoadBalancer"
    Service = "newyork"
  }
}

// Target Group
resource "aws_lb_target_group" "newyork-tg" {
  name        = "newyork-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.new_york.id
  provider    = aws.new_york
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
    Name    = "newyork-tg"
    Service = "NewYorkTG"
  }
}

// Listener
resource "aws_lb_listener" "newyork_http" {
  load_balancer_arn = aws_lb.newyork_alb.arn
  port              = 80
  protocol          = "HTTP"
  provider          = aws.new_york

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.newyork-tg.arn
  }
}

// Launch Template
resource "aws_launch_template" "newyork_LT" {
  provider      = aws.new_york
  name          = "newyork_LT"
  image_id      = "ami-0453ec754f44f9a4a"
  instance_type = "t2.micro"

    user_data = filebase64("userdata.sh")

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.new_york_ec2_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "new_york-ec2-web-server"
    }
  }
}

// Auto Scaling Group
resource "aws_autoscaling_group" "new_york_ec2_asg" {
  max_size            = 3
  min_size            = 2
  desired_capacity    = 2
  name                = "new_york-web-server-asg"
  target_group_arns   = [aws_lb_target_group.newyork-tg.arn]
  vpc_zone_identifier = aws_subnet.private_subnet_NY[*].id
  provider            = aws.new_york

  launch_template {
    id      = aws_launch_template.newyork_LT.id
    version = "$Latest"
  }

  health_check_type = "EC2"
}

