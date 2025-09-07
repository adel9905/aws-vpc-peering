
# Create VPC B with CIDR block 10.1.0.0/16
resource "aws_vpc" "vpc_b" {
  cidr_block = "10.1.0.0/16"
}
# Attach an Internet Gateway to VPC B to allow external connectivity
resource "aws_internet_gateway" "igw_b" {
  vpc_id = aws_vpc.vpc_b.id
}
# Create a public subnet in VPC B with auto-assign public IP enabled
resource "aws_subnet" "subnet_vpc_b" {
  vpc_id                  = aws_vpc.vpc_b.id
  cidr_block              = "10.1.1.0/24"
  map_public_ip_on_launch = true
}
# Create a route table in VPC B with a default route to the Internet Gateway
resource "aws_route_table" "rt_b" {
  vpc_id = aws_vpc.vpc_b.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_b.id
  }
}
# Associate the public subnet with the route table
resource "aws_route_table_association" "rta_b" {
  subnet_id      = aws_subnet.subnet_vpc_b.id
  route_table_id = aws_route_table.rt_b.id
}
# Create a security group in VPC B allowing SSH and ICMP (ping) access
resource "aws_security_group" "allow_ping_ssh_b" {
  name   = "allow_ping_ssh"
  vpc_id = aws_vpc.vpc_b.id

  # Allow SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow ICMP (ping) from VPC A and from anywhere
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16", "0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch an EC2 instance in VPC B public subnet
resource "aws_instance" "vm_b" {
  ami                    = "ami-0c94855ba95c71c99"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet_vpc_b.id
  vpc_security_group_ids = [aws_security_group.allow_ping_ssh_b.id]
  key_name               = "key"
}
