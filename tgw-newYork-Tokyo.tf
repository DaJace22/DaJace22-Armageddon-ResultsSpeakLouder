variable "regions" {
  default = ["new_york"]
}

variable "hub_region" {
  default = "tokyo"
}
#############################################################
# TRANSIT GATEWAY
#############################################################
resource "aws_ec2_transit_gateway" "local_new_york" {
provider = aws.new_york
  description = "new_york"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support = "enable"
  tags = {
    Name = "new_york TGW"
  }
}
//Remove when not testing
resource "aws_ec2_transit_gateway" "peer" {
   provider = aws.tokyo
  description = "tokyo"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support = "enable"
  tags = {
    Name = "tokyo TGW"
  }
}
#############################################################
# TRANSIT GATEWAY VPC ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_vpc_attachment" "local_new_york_attachment" {
  provider = aws.new_york
  subnet_ids         = aws_subnet.private_subnet_NY[*].id
  transit_gateway_id = aws_ec2_transit_gateway.local_new_york.id
  vpc_id             = aws_vpc.new_york.id
  dns_support        = "enable"
   tags = {
    Name = "Attachment for tokyo"
  }
}
//Remove when not testing
resource "aws_ec2_transit_gateway_vpc_attachment" "peer_attachment" {
     provider = aws.tokyo

  subnet_ids         = aws_subnet.private_subnet_Tokyo[*].id
  transit_gateway_id = aws_ec2_transit_gateway.peer.id
  vpc_id             = aws_vpc.tokyo.id
  dns_support        = "enable"
  tags = {
    Name = "Attachment for tokyo"
  }
}

#############################################################
# TRANSIT GATEWAY PEERING ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_peering_attachment" "hub_to_spoke" {

  transit_gateway_id      = aws_ec2_transit_gateway.local_new_york.id # Hub TGW
  peer_transit_gateway_id = aws_ec2_transit_gateway.peer.id   # Spoke TGWs
  
  peer_region             = "ap-northeast-1"

  tags = {
    Name = "Hub to Spoke Peering new york"
  }

  provider = aws.new_york # Hub TGW provider
}
#############################################################
# TRANSIT GATEWAY PEERING ACCEPTER
#############################################################
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "spoke_accept" {


  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke.id
  provider                      = aws.tokyo
  tags = {
    Name = "Spoke Accept Hub Peering tokyo"
  }
}
#############################################################
# TRANSIT GATEWAY ROUTE TABLE CONFIGURATION
#############################################################

resource "aws_ec2_transit_gateway_route_table" "hub_route_table" {
  transit_gateway_id = aws_ec2_transit_gateway.peer.id
  tags = {
    Name = "Hub TGW Route Table (Tokyo)"
  }
  provider = aws.tokyo
}

resource "aws_ec2_transit_gateway_route_table" "spoke_route_table" {
  transit_gateway_id = aws_ec2_transit_gateway.local_new_york.id

  tags = {
    Name = "Spoke TGW Route Table (New York)"
  }
  provider = aws.new_york
}

#############################################################
# TRANSIT GATEWAY ROUTE TABLE ASSOCIATIONS
#############################################################

# Associate Hub TGW Route Table with Tokyo VPC Attachment
resource "aws_ec2_transit_gateway_route_table_association" "hub_tgw_vpc" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table.id
  provider = aws.tokyo
}

# Associate Spoke TGW Route Table with New York VPC Attachment
resource "aws_ec2_transit_gateway_route_table_association" "spoke_tgw_vpc" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.local_new_york_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table.id
  provider = aws.new_york
}
# Associate Spoke TGW Route Table with New York Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table.id

  provider = aws.new_york

}
# Associate Hub TGW Route Table with Tokyo Peering Attachment
resource "aws_ec2_transit_gateway_route_table_association" "tgw_attachment_association_peer" {
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table.id

  provider = aws.tokyo

}

#############################################################
# TRANSIT GATEWAY ROUTES
#############################################################

# Route from Hub TGW to Spoke VPC (Tokyo -> New York)
resource "aws_ec2_transit_gateway_route" "hub_to_spoke" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table.id
  destination_cidr_block         = aws_vpc.new_york.cidr_block # New York VPC CIDR
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke.id
  provider                       = aws.tokyo

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.local_new_york_attachment]
}

# Route from Hub TGW to Tokyo VPC (Tokyo -> Tokyo VPC CIDR)
resource "aws_ec2_transit_gateway_route" "hub_to_hub_vpc" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub_route_table.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block # Tokyo VPC CIDR
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.peer_attachment.id
  provider                       = aws.tokyo
}

# Route from Spoke TGW to Hub VPC (New York -> Tokyo)
resource "aws_ec2_transit_gateway_route" "spoke_to_hub" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table.id
  destination_cidr_block         = aws_vpc.tokyo.cidr_block # Tokyo VPC CIDR
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke.id
  provider                       = aws.new_york

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.peer_attachment]
}

# Route from Spoke TGW to New York VPC (New York -> New York VPC CIDR)
resource "aws_ec2_transit_gateway_route" "spoke_to_spoke_vpc" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_route_table.id
  destination_cidr_block         = aws_vpc.new_york.cidr_block # New York VPC CIDR
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.local_new_york_attachment.id
  provider                       = aws.new_york
}
#############################################################
# VPC ROUTE TABLE CONFIGURATION
#############################################################

# Route for Hub VPC (Tokyo) to Reach Spoke VPC (New York)
resource "aws_route" "hub_to_spoke" {
  route_table_id         = aws_route_table.tokyo_route_table_private_subnet.id
  destination_cidr_block = aws_vpc.new_york.cidr_block # New York VPC CIDR
  transit_gateway_id     = aws_ec2_transit_gateway.peer.id
  provider               = aws.tokyo
}

# Route for Spoke VPC (New York) to Reach Hub VPC (Tokyo)
resource "aws_route" "spoke_to_hub" {
  route_table_id         = aws_route_table.new_york_route_table_public_subnet.id
  destination_cidr_block = aws_vpc.tokyo.cidr_block # Tokyo VPC CIDR
  transit_gateway_id     = aws_ec2_transit_gateway.local_new_york.id
  provider               = aws.new_york
}

