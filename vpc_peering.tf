##########################################
# VPC Peering between VPC A and VPC B
##########################################

# Create a VPC peering connection between VPC A and VPC B
resource "aws_vpc_peering_connection" "peer" {
  vpc_id      = aws_vpc.vpc1.id
  peer_vpc_id = aws_vpc.vpc_b.id
  auto_accept = true
}

# Add route in VPC A route table to reach VPC B via peering connection
resource "aws_route" "peer_route_a" {
  route_table_id            = aws_route_table.rt-gw.id
  destination_cidr_block    = aws_vpc.vpc_b.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}
# Add route in VPC B route table to reach VPC A via peering connection
resource "aws_route" "peer_route_b" {
  route_table_id            = aws_route_table.rt_b.id
  destination_cidr_block    = aws_vpc.vpc1.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}
# Add route in VPC A private route table to reach VPC B
resource "aws_route" "peer_route_a_private" {
  route_table_id            = aws_route_table.rt_a_private.id
  destination_cidr_block    = aws_vpc.vpc_b.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}
