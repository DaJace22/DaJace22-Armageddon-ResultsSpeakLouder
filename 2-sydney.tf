variable "vpc_availability_zone_sydney" {
  type        = list(string)
  description = "Availability Zone"
  default     = ["ap-southeast-2a", "ap-southeast-2b"]
}

// VPC
resource "aws_vpc" "sydney" {
  cidr_block           = "10.74.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  provider             = aws.sydney
  tags = {
    Name = "sydney VPC"
  }
}

// Subnets
resource "aws_subnet" "public_subnet_sydney" {
  vpc_id            = aws_vpc.sydney.id
  count             = length(var.vpc_availability_zone_sydney)
  cidr_block        = cidrsubnet(aws_vpc.sydney.cidr_block, 8, count.index + 1)
  availability_zone = element(var.vpc_availability_zone_sydney, count.index)
  provider          = aws.sydney
  tags = {
    Name = "sydney Public Subnet${count.index + 1}",
  }
}

resource "aws_subnet" "private_subnet_sydney" {
  vpc_id            = aws_vpc.sydney.id
  count             = length(var.vpc_availability_zone_sydney)
  cidr_block        = cidrsubnet(aws_vpc.sydney.cidr_block, 8, count.index + 11)
  availability_zone = element(var.vpc_availability_zone_sydney, count.index)
  provider          = aws.sydney
  tags = {
    Name = "sydney Private Subnet${count.index + 1}",
  }
}

// IGW
resource "aws_internet_gateway" "sydney_igw" {
  vpc_id   = aws_vpc.sydney.id
  provider = aws.sydney

  tags = {
    Name = "sydney_igw"
  }
}

// RT for the public subnet
resource "aws_route_table" "sydney_route_table_public_subnet" {
  vpc_id   = aws_vpc.sydney.id
  provider = aws.sydney

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sydney_igw.id
  }

  tags = {
    Name = "Route Table for Public Subnet",
  }

}

// Association between RT and IG
resource "aws_route_table_association" "sydney_public_subnet_association" {
  route_table_id = aws_route_table.sydney_route_table_public_subnet.id
  count          = length((var.vpc_availability_zone_sydney))
  subnet_id      = element(aws_subnet.public_subnet_sydney[*].id, count.index)
  provider       = aws.sydney
}

// EIP
resource "aws_eip" "sydney_eip" {
  domain   = "vpc"
  provider = aws.sydney
}

// NAT
resource "aws_nat_gateway" "sydney_nat" {
  allocation_id = aws_eip.sydney_eip.id
  subnet_id     = aws_subnet.public_subnet_sydney[0].id
  provider      = aws.sydney
}

// RT for private Subnet
resource "aws_route_table" "sydney_route_table_private_subnet" {
  vpc_id   = aws_vpc.sydney.id
  provider = aws.sydney

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.sydney_nat.id
  }

  route {
    cidr_block         = "10.70.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.local_sydney.id
  }

  tags = {
    Name = "Route Table for Private Subnet",
  }

}

// RT Association Private
resource "aws_route_table_association" "sydney_private_subnet_association" {
  route_table_id = aws_route_table.sydney_route_table_private_subnet.id
  count          = length((var.vpc_availability_zone_sydney))
  subnet_id      = element(aws_subnet.private_subnet_sydney[*].id, count.index)
  provider       = aws.sydney
}

// Security Groups
resource "aws_security_group" "sydney_alb_sg" {
  name        = "sydney-alb-sg"
  description = "Security Group for Application Load Balancer"
  provider    = aws.sydney

  vpc_id = aws_vpc.sydney.id

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
    Name = "sydney-alb-sg"
  }
}

// Security Group For EC2
resource "aws_security_group" "sydney_ec2_sg" {
  name        = "sydney-ec2-sg"
  description = "Security Group for Webserver Instance"
  provider    = aws.sydney

  vpc_id = aws_vpc.sydney.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "TCP"
    security_groups = [aws_security_group.sydney_alb_sg.id]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sydney-ec2-sg"
  }
}

// Load Balancer
resource "aws_lb" "sydney_alb" {
  name                       = "sydney-load-balancer"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = aws_subnet.public_subnet_sydney[*].id
  depends_on                 = [aws_internet_gateway.sydney_igw]
  enable_deletion_protection = false
  provider                   = aws.sydney

  tags = {
    Name    = "sydneyLoadBalancer"
    Service = "sydney"
  }
}

// Target Group
resource "aws_lb_target_group" "sydney-tg" {
  name        = "sydney-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.sydney.id
  provider    = aws.sydney
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
    Name    = "sydney-tg"
    Service = "sydneyTG"
  }
}

// Listener
resource "aws_lb_listener" "sydney_http" {
  load_balancer_arn = aws_lb.sydney_alb.arn
  port              = 80
  protocol          = "HTTP"
  provider          = aws.sydney

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sydney-tg.arn
  }
}

// Launch Template
resource "aws_launch_template" "sydney_LT" {
  provider      = aws.sydney
  name_prefix   = "sydney_LT"
  image_id      = "ami-0a8f40a451672ea1d"
  instance_type = "t2.micro"

  user_data = filebase64("userdata.sh")

    network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.sydney_ec2_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "sydney-ec2-web-server"
    }
  }
}

// Auto Scaling Group
resource "aws_autoscaling_group" "sydney_ec2_asg" {
  max_size            = 3
  min_size            = 2
  desired_capacity    = 2
  name                = "sydney-web-server-asg"
  target_group_arns   = [aws_lb_target_group.sydney-tg.id]
  vpc_zone_identifier = aws_subnet.private_subnet_sydney[*].id
  provider            = aws.sydney

  launch_template {
    id      = aws_launch_template.sydney_LT.id
    version = "$Latest"
  }

  health_check_type = "EC2"
}
