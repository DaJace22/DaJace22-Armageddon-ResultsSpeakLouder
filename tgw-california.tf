variable "regions_CA" {
  default = ["california"]
}

variable "hub_region_CA" {
  default = "tokyo" 
}

#############################################################
# TRANSIT GATEWAY - california
#############################################################
resource "aws_ec2_transit_gateway" "local_california" {
  provider = aws.california 
  description = "california"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support = "enable"
  tags = {
    Name = "california TGW" 
  }
}

#############################################################
# TRANSIT GATEWAY VPC ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_vpc_attachment" "local_california_attachment" {
  provider = aws.california 
  subnet_ids         = aws_subnet.private_subnet_California[*].id 
  transit_gateway_id = aws_ec2_transit_gateway.local_california.id
  vpc_id             = aws_vpc.california.id 
  dns_support        = "enable"
  tags = {
    Name = "Attachment for tokyo" 
  }
}

#############################################################
# TRANSIT GATEWAY PEERING ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_peering_attachment" "hub_to_spoke_california" {
  transit_gateway_id      = aws_ec2_transit_gateway.local_california.id 
  peer_transit_gateway_id = aws_ec2_transit_gateway.peer.id 
  peer_region             = "ap-northeast-1" 
  tags = {
    Name = "Hub to Spoke Peering new york" 
  }
  provider = aws.california 
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "spoke_accept_tko_california" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_california.id
  provider                      = aws.tokyo 
  tags = {
    Name = "Spoke Accept Hub Peering tokyo"
  }
}

#############################################################
# TRANSIT GATEWAY ROUTE TABLE CONFIGURATION
#############################################################

resource "aws_ec2_transit_gateway_route_table" "hub_route_table_tko_california" {
  transit_gateway_id = aws_ec2_transit_gateway.peer.id 
  tags = {
    Name = "Hub TGW Route Table (Tokyo)"
  }
  provider = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route_table" "spoke_route_table_california" {
  transit_gateway_id = aws_ec2_transit_gateway.local_california.id 
  tags = {
    Name = "Spoke TGW Route Table (California)" 
  }
  provider = aws.california 
}
#############################################################
# TRANSIT GATEWAY ROUTE TABLE ASSOCIATIONS
#############################################################

# Associate Hub TGW Route Table with Tokyo VPC Attachment
#resource "aws_ec2_transit_gateway_route_table_association" "hub_tgw_vpc_california" {
#  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
#  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_california.id
#  provider = aws.tokyo
#}

# Associate Spoke TGW Route Table with New York VPC Attachment
resource "aws_ec2_transit_gateway_route_table_association" "spoke_tgw_vpc_california" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.local_california_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_california.id
  provider = aws.california
}
# Associate Spoke TGW Route Table with New York Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association_california" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_california.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_california.id

  provider = aws.california

}
# Associate Hub TGW Route Table with Tokyo Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association_peer_california" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_california.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_california.id

  provider = aws.tokyo

}
#############################################################
# TRANSIT GATEWAY ROUTES
#############################################################

resource "aws_ec2_transit_gateway_route" "hub_to_spoke_tko_california" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_california.id
  destination_cidr_block         = aws_vpc.california.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_california.id
  provider                       = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route" "hub_to_hub_vpc_tko_california" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_california.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
  provider                       = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route" "spoke_to_hub_california" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_california.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_california.id
  provider                       = aws.california 
}

resource "aws_ec2_transit_gateway_route" "spoke_to_spoke_vpc_california" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_california.id
  destination_cidr_block         = aws_vpc.california.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.local_california_attachment.id
  provider                       = aws.california 
}

#############################################################
# VPC ROUTE TABLE CONFIGURATION
#############################################################

resource "aws_route" "spoke_to_hub_california" {
  route_table_id         = aws_route_table.california_route_table_public_subnet.id 
  destination_cidr_block = aws_vpc.tokyo.cidr_block 
  transit_gateway_id     = aws_ec2_transit_gateway.local_california.id
  provider               = aws.california 
}
