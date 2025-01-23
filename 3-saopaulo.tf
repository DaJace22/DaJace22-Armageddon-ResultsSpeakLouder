variable "vpc_availability_zone_saopaulo" {
  type        = list(string)
  description = "Availability Zone"
  default     = ["sa-east-1a", "sa-east-1c"]
}

//VPC
resource "aws_vpc" "saopaulo" {
  cidr_block           = "10.73.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  provider             = aws.sao_paulo
  tags = {
    Name = "saopaulo VPC"
  }
}

// Subnets
resource "aws_subnet" "public_subnet_saopaulo" {
  vpc_id            = aws_vpc.saopaulo.id
  count             = length(var.vpc_availability_zone_saopaulo)
  cidr_block        = cidrsubnet(aws_vpc.saopaulo.cidr_block, 8, count.index + 1)
  availability_zone = element(var.vpc_availability_zone_saopaulo, count.index)
  provider          = aws.sao_paulo
  tags = {
    Name = "sao paulo Public Subnet${count.index + 1}",
  }
}

resource "aws_subnet" "private_subnet_saopaulo" {
  vpc_id            = aws_vpc.saopaulo.id
  count             = length(var.vpc_availability_zone_saopaulo)
  cidr_block        = cidrsubnet(aws_vpc.saopaulo.cidr_block, 8, count.index + 11)
  availability_zone = element(var.vpc_availability_zone_saopaulo, count.index)
  provider          = aws.sao_paulo
  tags = {
    Name = "sao paulo Private Subnet${count.index + 1}",
  }
}

// IGW
resource "aws_internet_gateway" "saopaulo_igw" {
  vpc_id   = aws_vpc.saopaulo.id
  provider = aws.sao_paulo

  tags = {
    Name = "saopaulo_igw"
  }
}

// RT for the public subnet
resource "aws_route_table" "sao_paulo_route_table_public_subnet" {
  vpc_id   = aws_vpc.saopaulo.id
  provider = aws.sao_paulo

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.saopaulo_igw.id
  }

  tags = {
    Name = "Route Table for Public Subnet",
  }

}

// Association between RT and IG
resource "aws_route_table_association" "sao_paulo_public_subnet_association" {
  route_table_id = aws_route_table.sao_paulo_route_table_public_subnet.id
  count          = length((var.vpc_availability_zone_saopaulo))
  subnet_id      = element(aws_subnet.public_subnet_saopaulo[*].id, count.index)
  provider       = aws.sao_paulo
}

// EIP
resource "aws_eip" "sao_paulo_eip" {
  domain   = "vpc"
  provider = aws.sao_paulo
}

// NAT
resource "aws_nat_gateway" "sao_paulo_nat" {
  allocation_id = aws_eip.sao_paulo_eip.id
  subnet_id     = aws_subnet.public_subnet_saopaulo[0].id
  provider      = aws.sao_paulo
}

// RT for private Subnet
resource "aws_route_table" "sao_paulo_route_table_private_subnet" {
  vpc_id   = aws_vpc.saopaulo.id
  provider = aws.sao_paulo

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.sao_paulo_nat.id
  }

  route {
    cidr_block         = "10.70.0.0/16"
    transit_gateway_id = aws_ec2_transit_gateway.local_saopaulo.id
  }

  tags = {
    Name = "Route Table for Private Subnet",
  }

}

// RT Association Private
resource "aws_route_table_association" "sao_paulo_private_subnet_association" {
  route_table_id = aws_route_table.sao_paulo_route_table_private_subnet.id
  count          = length((var.vpc_availability_zone_saopaulo))
  subnet_id      = element(aws_subnet.private_subnet_saopaulo[*].id, count.index)
  provider       = aws.sao_paulo
}

// Security Groups
resource "aws_security_group" "sao_paulo_alb_sg" {
  name        = "sao_paulo-alb-sg"
  description = "Security Group for Application Load Balancer"
  provider    = aws.sao_paulo

  vpc_id = aws_vpc.saopaulo.id

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
    Name = "sao_paulo-alb-sg"
  }
}

// Security Group For EC2
resource "aws_security_group" "sao_paulo_ec2_sg" {
  name        = "sao_paulo-ec2-sg"
  description = "Security Group for Webserver Instance"
  provider    = aws.sao_paulo

  vpc_id = aws_vpc.saopaulo.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "TCP"
    security_groups = [aws_security_group.sao_paulo_alb_sg.id]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sao_paulo-ec2-sg"
  }
}

// Load Balancer
resource "aws_lb" "saopaulo_alb" {
  name                       = "saopaulo-load-balancer"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = aws_subnet.private_subnet_saopaulo[*].id
  depends_on                 = [aws_internet_gateway.saopaulo_igw]
  enable_deletion_protection = false
  provider                   = aws.sao_paulo

  tags = {
    Name    = "saopauloLoadBalancer"
    Service = "saopaulo"
  }
}

// Target Group
resource "aws_lb_target_group" "saopaulo-tg" {
  name        = "saopaulo-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.saopaulo.id
  provider    = aws.sao_paulo
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
    Name    = "saopaulo-tg"
    Service = "SaoPauloTG"
  }
}

// Listener
resource "aws_lb_listener" "saopaulo_http" {
  load_balancer_arn = aws_lb.saopaulo_alb.arn
  port              = 80
  protocol          = "HTTP"
  provider          = aws.sao_paulo

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.saopaulo-tg.arn
  }
}

// Launch Template
resource "aws_launch_template" "saopaulo_LT" {
  provider      = aws.sao_paulo
  name          = "saopaulo_LT"
  image_id      = "ami-02576955a77abf0e6"
  instance_type = "t2.micro"

    user_data = filebase64("userdata.sh")

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.sao_paulo_ec2_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "sao_paulo-ec2-web-server"
    }
  }
}

// Auto Scaling Group
resource "aws_autoscaling_group" "sao_paulo_ec2_asg" {
  max_size            = 3
  min_size            = 2
  desired_capacity    = 2
  name                = "sao_paulo-web-server-asg"
  target_group_arns   = [aws_lb_target_group.saopaulo-tg.arn]
  vpc_zone_identifier = aws_subnet.private_subnet_saopaulo[*].id
  provider            = aws.sao_paulo

  launch_template {
    id      = aws_launch_template.saopaulo_LT.id
    version = "$Latest"
  }

  health_check_type = "EC2"
}
