variable "regions_sy" {
  default = ["sydney"]
}

variable "hub_region_sy" {
  default = "tokyo" 
}

#############################################################
# TRANSIT GATEWAY - sydney
#############################################################
resource "aws_ec2_transit_gateway" "local_sydney" {
  provider = aws.sydney 
  description = "sydney"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support = "enable"
  tags = {
    Name = "sydney TGW" 
  }
}

#############################################################
# TRANSIT GATEWAY VPC ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_vpc_attachment" "local_sydney_attachment" {
  provider = aws.sydney 
  subnet_ids         = aws_subnet.private_subnet_sydney[*].id 
  transit_gateway_id = aws_ec2_transit_gateway.local_sydney.id
  vpc_id             = aws_vpc.sydney.id 
  dns_support        = "enable"
  tags = {
    Name = "Attachment for tokyo" 
  }
}

#############################################################
# TRANSIT GATEWAY PEERING ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_peering_attachment" "hub_to_spoke_sydney" {
  transit_gateway_id      = aws_ec2_transit_gateway.local_sydney.id 
  peer_transit_gateway_id = aws_ec2_transit_gateway.peer.id 
  peer_region             = "ap-northeast-1" 
  tags = {
    Name = "Hub to Spoke Peering sydney" 
  }
  provider = aws.sydney 
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "spoke_accept_tko_sydney" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_sydney.id
  provider                      = aws.tokyo 
  tags = {
    Name = "Spoke Accept Hub Peering tokyo"
  }
}

#############################################################
# TRANSIT GATEWAY ROUTE TABLE CONFIGURATION
#############################################################

resource "aws_ec2_transit_gateway_route_table" "hub_route_table_tko_sydney" {
  transit_gateway_id = aws_ec2_transit_gateway.peer.id 
  tags = {
    Name = "Hub TGW Route Table (Tokyo)"
  }
  provider = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route_table" "spoke_route_table_sydney" {
  transit_gateway_id = aws_ec2_transit_gateway.local_sydney.id 
  tags = {
    Name = "Spoke TGW Route Table (sydney)" 
  }
  provider = aws.sydney 
}
#############################################################
# TRANSIT GATEWAY ROUTE TABLE ASSOCIATIONS
#############################################################

# Associate Hub TGW Route Table with Tokyo VPC Attachment
#resource "aws_ec2_transit_gateway_route_table_association" "hub_tgw_vpc_sydney" {
#  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
#  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_sydney.id
#  provider = aws.tokyo
#}

# Associate Spoke TGW Route Table with New York VPC Attachment
resource "aws_ec2_transit_gateway_route_table_association" "spoke_tgw_vpc_sydney" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.local_sydney_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_sydney.id
  provider = aws.sydney
}
# Associate Spoke TGW Route Table with New York Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association_sydney" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_sydney.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_sydney.id

  provider = aws.sydney

}
# Associate Hub TGW Route Table with Tokyo Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association_peer_sydney" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_sydney.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_sydney.id

  provider = aws.tokyo

}
#############################################################
# TRANSIT GATEWAY ROUTES
#############################################################

resource "aws_ec2_transit_gateway_route" "hub_to_spoke_tko_sydney" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_sydney.id
  destination_cidr_block         = aws_vpc.sydney.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_sydney.id
  provider                       = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route" "hub_to_hub_vpc_tko_sydney" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_sydney.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
  provider                       = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route" "spoke_to_hub_sydney" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_sydney.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_sydney.id
  provider                       = aws.sydney 
}

resource "aws_ec2_transit_gateway_route" "spoke_to_spoke_vpc_sydney" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_sydney.id
  destination_cidr_block         = aws_vpc.sydney.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.local_sydney_attachment.id
  provider                       = aws.sydney 
}

#############################################################
# VPC ROUTE TABLE CONFIGURATION
#############################################################

resource "aws_route" "spoke_to_hub_sydney" {
  route_table_id         = aws_route_table.sydney_route_table_public_subnet.id 
  destination_cidr_block = aws_vpc.tokyo.cidr_block 
  transit_gateway_id     = aws_ec2_transit_gateway.local_sydney.id
  provider               = aws.sydney 
}
