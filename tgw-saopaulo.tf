variable "regions_sp" {
  default = ["saopaulo"]
}

variable "hub_region_sp" {
  default = "tokyo" 
}

#############################################################
# TRANSIT GATEWAY - saopaulo
#############################################################
resource "aws_ec2_transit_gateway" "local_saopaulo" {
  provider = aws.sao_paulo 
  description = "saopaulo"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support = "enable"
  tags = {
    Name = "saopaulo TGW" 
  }
}

#############################################################
# TRANSIT GATEWAY VPC ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_vpc_attachment" "local_saopaulo_attachment" {
  provider = aws.sao_paulo 
  subnet_ids         = aws_subnet.private_subnet_saopaulo[*].id 
  transit_gateway_id = aws_ec2_transit_gateway.local_saopaulo.id
  vpc_id             = aws_vpc.saopaulo.id 
  dns_support        = "enable"
  tags = {
    Name = "Attachment for tokyo" 
  }
}

#############################################################
# TRANSIT GATEWAY PEERING ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_peering_attachment" "hub_to_spoke_saopaulo" {
  transit_gateway_id      = aws_ec2_transit_gateway.local_saopaulo.id 
  peer_transit_gateway_id = aws_ec2_transit_gateway.peer.id 
  peer_region             = "ap-northeast-1" 
  tags = {
    Name = "Hub to Spoke Peering sao paulo" 
  }
  provider = aws.sao_paulo 
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "spoke_accept_tko_saopaulo" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_saopaulo.id
  provider                      = aws.tokyo 
  tags = {
    Name = "Spoke Accept Hub Peering tokyo"
  }
}

#############################################################
# TRANSIT GATEWAY ROUTE TABLE CONFIGURATION
#############################################################

resource "aws_ec2_transit_gateway_route_table" "hub_route_table_tko_saopaulo" {
  transit_gateway_id = aws_ec2_transit_gateway.peer.id 
  tags = {
    Name = "Hub TGW Route Table (Tokyo)"
  }
  provider = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route_table" "spoke_route_table_saopaulo" {
  transit_gateway_id = aws_ec2_transit_gateway.local_saopaulo.id 
  tags = {
    Name = "Spoke TGW Route Table (saopaulo)" 
  }
  provider = aws.sao_paulo 
}
#############################################################
# TRANSIT GATEWAY ROUTE TABLE ASSOCIATIONS
#############################################################

# Associate Hub TGW Route Table with Tokyo VPC Attachment
#resource "aws_ec2_transit_gateway_route_table_association" "hub_tgw_vpc_saopaulo" {
#  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
#  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_saopaulo.id
#  provider = aws.tokyo
#}

# Associate Spoke TGW Route Table with New York VPC Attachment
resource "aws_ec2_transit_gateway_route_table_association" "spoke_tgw_vpc_saopaulo" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.local_saopaulo_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_saopaulo.id
  provider = aws.sao_paulo
}
# Associate Spoke TGW Route Table with New York Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association_saopaulo" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_saopaulo.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_saopaulo.id

  provider = aws.sao_paulo

}
# Associate Hub TGW Route Table with Tokyo Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association_peer_saopaulo" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_saopaulo.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_saopaulo.id

  provider = aws.tokyo

}
#############################################################
# TRANSIT GATEWAY ROUTES
#############################################################

resource "aws_ec2_transit_gateway_route" "hub_to_spoke_tko_saopaulo" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_saopaulo.id
  destination_cidr_block         = aws_vpc.saopaulo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_saopaulo.id
  provider                       = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route" "hub_to_hub_vpc_tko_saopaulo" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table_tko_saopaulo.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
  provider                       = aws.tokyo 
}

resource "aws_ec2_transit_gateway_route" "spoke_to_hub_saopaulo" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_saopaulo.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke_saopaulo.id
  provider                       = aws.sao_paulo 
}

resource "aws_ec2_transit_gateway_route" "spoke_to_spoke_vpc_saopaulo" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table_saopaulo.id
  destination_cidr_block         = aws_vpc.saopaulo.cidr_block 
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.local_saopaulo_attachment.id
  provider                       = aws.sao_paulo 
}

#############################################################
# VPC ROUTE TABLE CONFIGURATION
#############################################################

resource "aws_route" "spoke_to_hub_saopaulo" {
  route_table_id         = aws_route_table.sao_paulo_route_table_public_subnet.id 
  destination_cidr_block = aws_vpc.tokyo.cidr_block 
  transit_gateway_id     = aws_ec2_transit_gateway.local_saopaulo.id
  provider               = aws.sao_paulo 
}
