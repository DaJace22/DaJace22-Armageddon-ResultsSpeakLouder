variable "vpc_availability_zone_California" {
  type        = list(string)
  description = "Availability Zone"
  default     = ["us-west-1a", "us-west-1b"]
}

// VPC
resource "aws_vpc" "california" {
  cidr_block           = "10.75.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  provider             = aws.california
  tags = {
    Name = "California VPC"
  }
}

// Subnets
resource "aws_subnet" "public_subnet_California" {
  vpc_id            = aws_vpc.california.id
  count             = length(var.vpc_availability_zone_California)
  cidr_block        = cidrsubnet(aws_vpc.california.cidr_block, 8, count.index + 1)
  availability_zone = element(var.vpc_availability_zone_California, count.index)
  provider          = aws.california
  tags = {
    Name = "California Public Subnet${count.index + 1}",
  }
}

resource "aws_subnet" "private_subnet_California" {
  vpc_id            = aws_vpc.california.id
  count             = length(var.vpc_availability_zone_California)
  cidr_block        = cidrsubnet(aws_vpc.california.cidr_block, 8, count.index + 11)
  availability_zone = element(var.vpc_availability_zone_California, count.index)
  provider          = aws.california
  tags = {
    Name = "California Private Subnet${count.index + 1}",
  }
}

// IGW
resource "aws_internet_gateway" "california_igw" {
  vpc_id   = aws_vpc.california.id
  provider = aws.california

  tags = {
    Name = "california_igw"
  }
}

// RT for the public subnet
resource "aws_route_table" "california_route_table_public_subnet" {
  vpc_id   = aws_vpc.california.id
  provider = aws.california

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.california_igw.id
  }

  tags = {
    Name = "Route Table for Public Subnet",
  }

}

// Association between RT and IG
resource "aws_route_table_association" "california_public_subnet_association" {
  route_table_id = aws_route_table.california_route_table_public_subnet.id
  count          = length((var.vpc_availability_zone_California))
  subnet_id      = element(aws_subnet.public_subnet_California[*].id, count.index)
  provider       = aws.california
}

// EIP
resource "aws_eip" "california_eip" {
  domain   = "vpc"
  provider = aws.california
}

// NAT
resource "aws_nat_gateway" "california_nat" {
  allocation_id = aws_eip.california_eip.id
  subnet_id     = aws_subnet.public_subnet_California[0].id
  provider      = aws.california
}

// RT for private Subnet
resource "aws_route_table" "california_route_table_private_subnet" {
  vpc_id   = aws_vpc.california.id
  provider = aws.california

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.california_nat.id
  }

  route {
    cidr_block         = "10.70.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.local_california.id
  }

  tags = {
    Name = "Route Table for Private Subnet",
  }

}

// RT Association Private
resource "aws_route_table_association" "california_private_subnet_association" {
  route_table_id = aws_route_table.california_route_table_private_subnet.id
  count          = length((var.vpc_availability_zone_California))
  subnet_id      = element(aws_subnet.private_subnet_California[*].id, count.index)
  provider       = aws.california
}

// Security Groups
resource "aws_security_group" "california_alb_sg" {
  name        = "california-alb-sg"
  description = "Security Group for Application Load Balancer"
  provider    = aws.california

  vpc_id = aws_vpc.california.id

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
    Name = "california-alb-sg"
  }
}

// Security Group For EC2
resource "aws_security_group" "california_ec2_sg" {
  name        = "california-ec2-sg"
  description = "Security Group for Webserver Instance"
  provider    = aws.california

  vpc_id = aws_vpc.california.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "TCP"
    security_groups = [aws_security_group.california_alb_sg.id]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "california-ec2-sg"
  }
}

// Load Balancer
resource "aws_lb" "california_alb" {
  name                       = "california-load-balancer"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = aws_subnet.public_subnet_California[*].id
  depends_on                 = [aws_internet_gateway.california_igw]
  enable_deletion_protection = false
  provider                   = aws.california

  tags = {
    Name    = "CaliforniaLoadBalancer"
    Service = "california"
  }
}

// Target Group
resource "aws_lb_target_group" "california-tg" {
  name        = "california-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.california.id
  provider    = aws.california
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
    Name    = "california-tg"
    Service = "CaliforniaTG"
  }
}

// Listener
resource "aws_lb_listener" "california_http" {
  load_balancer_arn = aws_lb.california_alb.arn
  port              = 80
  protocol          = "HTTP"
  provider          = aws.california

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.california-tg.arn
  }
}

// Launch Template
resource "aws_launch_template" "california_LT" {
  provider      = aws.california
  name_prefix   = "california_LT"
  image_id      = "ami-038bba9a164eb3dc1"
  instance_type = "t2.micro"

  user_data = filebase64("userdata.sh")

    network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.california_ec2_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "california-ec2-web-server"
    }
  }
}

// Auto Scaling Group
resource "aws_autoscaling_group" "california_ec2_asg" {
  max_size            = 3
  min_size            = 2
  desired_capacity    = 2
  name                = "california-web-server-asg"
  target_group_arns   = [aws_lb_target_group.california-tg.id]
  vpc_zone_identifier = aws_subnet.private_subnet_California[*].id
  provider            = aws.california

  launch_template {
    id      = aws_launch_template.california_LT.id
    version = "$Latest"
  }

  health_check_type = "EC2"
}
