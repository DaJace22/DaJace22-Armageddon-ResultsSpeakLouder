variable "regions_ld" {
  default = ["london"]
}

variable "hub_region_ld" {
  default = "tokyo" 
}

#############################################################
# TRANSIT GATEWAY - london
#############################################################
resource "aws_ec2_transit_gateway" "local_london" {
  provider = aws.london 
  description = "london"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support = "enable"
  tags = {
    Name = "london TGW" 
  }
}

#############################################################
# TRANSIT GATEWAY VPC ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_vpc_attachment" "local_london_attachment" {
  provider = aws.london 
  subnet_ids         = aws_subnet.private_subnet_london[*].id 
  transit_gateway_id = aws_ec2_transit_gateway.local_london.id
  vpc_id             = aws_vpc.london.id 
  dns_support        = "enable"
  tags = {
    Name = "Attachment for tokyo" 
  }
}

#############################################################
# TRANSIT GATEWAY PEERING ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_peering_attachment" "hub_to_spoke_london" {
  transit_gateway_id      = aws_ec2_transit_gateway.local_london.id 
  peer_transit_gateway_id = aws_ec2_transit_gateway.peer.id 
  peer_region             = "ap-northeast-1" 
  tags = {
    Name = "Hub to Spoke Peering new york" 
  }
  provider = aws.london 
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "spoke_accept_tko_london" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_london.id
  provider                      = aws.tokyo 
  tags = {
    Name = "Spoke Accept Hub Peering tokyo"
  }
}

#############################################################
# TRANSIT GATEWAY ROUTE TABLE CONFIGURATION
#############################################################

resource "aws_ec2_transit_gateway_route_table" "hub_route_table_tko_london" {
  transit_gateway_id = aws_ec2_transit_gateway.peer.id 
  tags = {
    Name = "Hub TGW Route Table (Tokyo)"
  }
  provider = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route_table" "spoke_route_table_london" {
  transit_gateway_id = aws_ec2_transit_gateway.local_london.id 
  tags = {
    Name = "Spoke TGW Route Table (london)" 
  }
  provider = aws.london 
}
#############################################################
# TRANSIT GATEWAY ROUTE TABLE ASSOCIATIONS
#############################################################

# Associate Hub TGW Route Table with Tokyo VPC Attachment
#resource "aws_ec2_transit_gateway_route_table_association" "hub_tgw_vpc_london" {
#  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
#  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_london.id
#  provider = aws.tokyo
#}

# Associate Spoke TGW Route Table with New York VPC Attachment
resource "aws_ec2_transit_gateway_route_table_association" "spoke_tgw_vpc_london" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.local_london_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_london.id
  provider = aws.london
}
# Associate Spoke TGW Route Table with New York Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association_london" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_london.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_london.id

  provider = aws.london

}
# Associate Hub TGW Route Table with Tokyo Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association_peer_london" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_london.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_london.id

  provider = aws.tokyo

}
#############################################################
# TRANSIT GATEWAY ROUTES
#############################################################

resource "aws_ec2_transit_gateway_route" "hub_to_spoke_tko_london" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_london.id
  destination_cidr_block         = aws_vpc.london.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_london.id
  provider                       = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route" "hub_to_hub_vpc_tko_london" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_london.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
  provider                       = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route" "spoke_to_hub_london" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_london.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_london.id
  provider                       = aws.london 
}

resource "aws_ec2_transit_gateway_route" "spoke_to_spoke_vpc_london" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_london.id
  destination_cidr_block         = aws_vpc.london.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.local_london_attachment.id
  provider                       = aws.london 
}

#############################################################
# VPC ROUTE TABLE CONFIGURATION
#############################################################

resource "aws_route" "spoke_to_hub_london" {
  route_table_id         = aws_route_table.london_route_table_public_subnet.id 
  destination_cidr_block = aws_vpc.tokyo.cidr_block 
  transit_gateway_id     = aws_ec2_transit_gateway.local_london.id
  provider               = aws.london 
}
