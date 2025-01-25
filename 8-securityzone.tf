// VPC
resource "aws_vpc" "security_zone" {
      cidr_block = "10.77.0.0/16" #Choose corresponding CIDR
      provider = aws.tokyo

  tags = {
    Name = "app1"
  }
  
}

// Subnet
resource "aws_subnet" "private-security-zone" { 
  vpc_id            = aws_vpc.security_zone.id
  cidr_block        = "10.77.0.0/24"
  availability_zone = "ap-northeast-1a" #Change to your AZ
  provider = aws.tokyo

  tags = {
    Name    = "private-security-zone" 
    Service = "logs-collection"
    Owner   = "Chewbacca"
    Planet  = "Musafar"
  }
}
resource "aws_subnet" "public-security-zone" { 
  vpc_id            = aws_vpc.security_zone.id
  cidr_block        = "10.77.1.0/24"
  availability_zone = "ap-northeast-1a" 
  map_public_ip_on_launch = true
  provider = aws.tokyo

  tags = {
    Name    = "public-security-zone" 
    Service = "logs-collection"
    Owner   = "Chewbacca"
    Planet  = "Musafar"
  }
}
resource "aws_eip" "eip" {
  domain = "vpc"
  provider = aws.tokyo


  tags = {
    Name = "nat-eip"
  }
}
// NAT
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public-security-zone.id
  provider = aws.tokyo
  tags = {
    Name = "nat-gateway"
  }
}

// Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.security_zone.id
provider = aws.tokyo
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
    route {
    cidr_block         = "10.70.0.0/24"
    transit_gateway_id = aws_ec2_transit_gateway.peer.id
  }

  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private-security-zone.id
  route_table_id = aws_route_table.private.id
provider = aws.tokyo

}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.security_zone.id
provider = aws.tokyo

  tags = {
    Name = "igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.security_zone.id
provider = aws.tokyo

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public-security-zone.id
  route_table_id = aws_route_table.public.id
provider = aws.tokyo

}

// IAM Role
resource "aws_iam_role" "siem_instance_role" {
  name = "siem-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy" "siem_policy" {
  role = aws_iam_role.siem_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:DescribeParameters",
          "ec2messages:GetMessages",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:SendReply"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

// Instance
resource "aws_instance" "SIEM_Server" {
  ami                         = "ami-08f52b2e87cebadd9"
  instance_type               = "t3.medium"
  key_name                    = "ArmageddonInTokyo" # Replace with your own key
  subnet_id                   = aws_subnet.private-security-zone.id
  vpc_security_group_ids      = [aws_security_group.SIEM_SG.id]
  iam_instance_profile        = aws_iam_instance_profile.siem_profile.id
provider = aws.tokyo


    root_block_device {
    volume_size = 20  
    volume_type = "gp3"  
  }

  user_data = filebase64("Grafana.sh")
  tags = {
    Name = "SIEM_Server"
  }
}
resource "aws_iam_instance_profile" "siem_profile" {
  name = "siem-instance-profile"
  role = aws_iam_role.siem_instance_role.name
provider = aws.tokyo

}
 

resource "aws_security_group" "SIEM_SG" {
    vpc_id = aws_vpc.security_zone.id
provider = aws.tokyo


    ingress {
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      cidr_blocks = ["${aws_instance.Bastion_Host.private_ip}/32"]
     
    }

    ingress {
        from_port   = 3100
        to_port     = 3100
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    
}

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["${aws_instance.Bastion_Host.private_ip}/32"]
    
}

    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
}

// Bastion Host
resource "aws_instance" "Bastion_Host" {
  ami                         = "ami-08f52b2e87cebadd9"
  instance_type               = "t2.micro"
  key_name                    = "ArmageddonInTokyo" # Replace with your own key
  subnet_id                   = aws_subnet.public-security-zone.id
  vpc_security_group_ids      = [aws_security_group.Bastion_instance.id]
provider = aws.tokyo



    root_block_device {
    volume_size = 8  
    volume_type = "gp2"  
  }
    tags = {
    Name = "Bastion_Host"
  }
}

resource "aws_security_group" "Bastion_instance" {
  name        = "Bastion_instance"
  description = "Bastion instance security group"
  vpc_id     = aws_vpc.security_zone.id
provider = aws.tokyo


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

// outputs
output "grafana_private_ip" {
  description = "The private IP of the Grafana server"
  value       = aws_instance.SIEM_Server.private_ip
}

output "bastion_public_ip" {
  description = "The public IP of the bastion host"
  value       = aws_instance.Bastion_Host.public_ip
}

resource "aws_ec2_transit_gateway_vpc_attachment" "local_siem_attachment" {
  provider = aws.tokyo 
  subnet_ids         = aws_subnet.private-security-zone[*].id 
  transit_gateway_id = aws_ec2_transit_gateway.peer.id
  vpc_id             = aws_vpc.security_zone.id 
  dns_support        = "enable"


  tags = {
    Name = "Attachment for tokyo" 
  }
}





