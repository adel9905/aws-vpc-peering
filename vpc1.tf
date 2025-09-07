##########################################
# VPC and Networking Setup
##########################################

# Create the main VPC with CIDR 10.0.0.0/16

resource "aws_vpc" "vpc1" {
  cidr_block = var.vpc1_cidr
  tags = {
    Name = "vpc1"
  }
}

# Public Subnet (10.0.1.0/24) in AZ us-east-1b
resource "aws_subnet" "publicsubnet-vpc1" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "publicsubnet-vpc1"
  }
}
# Internet Gateway for outbound internet access
resource "aws_internet_gateway" "gw-vpc1" {
  vpc_id = aws_vpc.vpc1.id

  tags = {
    Name = "igw-vpc1"
  }
}

# Route table for internet access (via IGW)
resource "aws_route_table" "rt-gw" {
  vpc_id = aws_vpc.vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw-vpc1.id
  }

  tags = {
    Name = "rt-gw"
  }
}

# Associate route table with public subnet to make it public
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.publicsubnet-vpc1.id
  route_table_id = aws_route_table.rt-gw.id
}

##########################################
# Bastion Host (Public EC2)
##########################################

# EC2 Bastion Host in public subnet
resource "aws_instance" "bastionhost" {
  ami                         = "ami-0150ccaf51ab55a51"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.publicsubnet-vpc1.id
  key_name                    = var.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sg.id]

  # User data installs Apache and serves a test page
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Hello from Terraform!" > /var/www/html/index.html
            EOF
  tags = {
    Name = "bastionhost"
  }
}

# Security Group for Bastion/Instances: allows SSH, HTTP, Flask (5000), and ICMP
resource "aws_security_group" "sg" {
  name   = "allow_ssh_http"
  vpc_id = aws_vpc.vpc1.id
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Allow SSH from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Allow Flask app port
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow ICMP (ping) from VPC B and everywhere
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.1.0.0/16", "0.0.0.0/0"]
  }
}

##########################################
# Private Subnet and Instance
##########################################

# Private subnet (10.0.2.0/24) with no direct internet access
resource "aws_subnet" "private_subnet-vpc1" {
  vpc_id     = aws_vpc.vpc1.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "privatesubnet-vpc1"
  }
}
##########################################
# NAT Gateway Setup
##########################################

# Elastic IP for NAT Gateway
resource "aws_eip" "lb" {
}

# NAT Gateway in public subnet (outbound internet for private subnets)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.lb.id
  subnet_id     = aws_subnet.publicsubnet2-vpc1.id

  tags = {
    Name = "nat-gw"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
}
# Private route table using NAT Gateway for outbound internet
resource "aws_route_table" "rt_a_private" {
  vpc_id = aws_vpc.vpc1.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}
# Associate private subnet with NAT-enabled route table
resource "aws_route_table_association" "rta_a_private" {
  subnet_id      = aws_subnet.private_subnet-vpc1.id
  route_table_id = aws_route_table.rt_a_private.id
}

##########################################
# Load Balancer Setup
##########################################

# Additional public subnet for HA load balancer
resource "aws_subnet" "publicsubnet2-vpc1" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "publicsubnet"
  }
}
# Associate route table with second public subnet
resource "aws_route_table_association" "association2" {
  subnet_id      = aws_subnet.publicsubnet2-vpc1.id
  route_table_id = aws_route_table.rt-gw.id
}
# Application Load Balancer (internet-facing, spans 2 public subnets)
resource "aws_lb" "loadbalancer1" {
  name               = "lb-tf"
  internal           = false #internet facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg.id]
  subnets            = [aws_subnet.publicsubnet2-vpc1.id, aws_subnet.publicsubnet-vpc1.id]
}

# Target group for web servers
resource "aws_lb_target_group" "tg" {
  name     = "tf-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc1.id
}
# Listener to forward traffic from LB to target group
resource "aws_lb_listener" "lbl" {
  load_balancer_arn = aws_lb.loadbalancer1.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}
##########################################
# Auto Scaling Group with Launch Template
##########################################

# Launch template for ASG instances (Apache installed)
resource "aws_launch_template" "launch_template1" {
  name_prefix   = "launch_template"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  key_name      = "key"

  vpc_security_group_ids = [aws_security_group.sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Hello, World from ASG , $(hostname -f)" > /var/www/html/index.html
              EOF
  )
  tags = {
    Name = "app-instance"
  }
}
# Second private subnet for ASG instances
resource "aws_subnet" "private_subnet2-vpc1" {
  vpc_id     = aws_vpc.vpc1.id
  cidr_block = "10.0.4.0/24"

  tags = {
    Name = "private_subnet2-vpc1"
  }
}
# Associate private subnet2 with NAT-enabled route table
resource "aws_route_table_association" "association3" {
  subnet_id      = aws_subnet.private_subnet2-vpc1.id
  route_table_id = aws_route_table.rt_a_private.id
}
# Auto Scaling Group (spans 2 private subnets, connected to ALB)
resource "aws_autoscaling_group" "asg" {
  launch_template {
    id      = aws_launch_template.launch_template1.id
    version = "$Latest"
  }
  name                = "asg"
  max_size            = 3
  min_size            = 1
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.private_subnet-vpc1.id, aws_subnet.private_subnet2-vpc1.id]
  target_group_arns   = [aws_lb_target_group.tg.arn]
  tag {
    key                 = "Name"
    value               = "web_instance"
    propagate_at_launch = true
  }
}

##########################################
# Private Subnets in VPC A for Database
##########################################

# Create private subnet 3 in VPC A (AZ: us-east-1a)
resource "aws_subnet" "private_subnet3" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private_subnet3"
  }
}
# Create private subnet 4 in VPC A (AZ: us-east-1b)
resource "aws_subnet" "private_subnet4" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private_subnet4"
  }
}

# Associate private subnets with VPC A's private route table
resource "aws_route_table_association" "rta_a_private_3" {
  subnet_id      = aws_subnet.private_subnet3.id
  route_table_id = aws_route_table.rt_a_private.id
}
resource "aws_route_table_association" "rta_a_private_4" {
  subnet_id      = aws_subnet.private_subnet4.id
  route_table_id = aws_route_table.rt_a_private.id
}

##########################################
# Database Subnet Group and RDS
##########################################

# Create an RDS subnet group with the private subnets in VPC A
resource "aws_db_subnet_group" "db_subnet" {
  name       = "main_db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet3.id, aws_subnet.private_subnet4.id]

  tags = {
    Name = "DB subnet group"
  }
}

# Security group allowing inbound MySQL (3306) traffic
resource "aws_security_group" "allow_mysql" {
  name   = "allow_mysql"
  vpc_id = aws_vpc.vpc1.id
  ingress {
    from_port   = 3306
    to_port     = 3306
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

# Launch an RDS MySQL instance in the private subnets
resource "aws_db_instance" "DB" {
  allocated_storage      = 10
  db_name                = "mydb"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  username               = "adel"
  password               = "password1234" # ⚠️ Consider using AWS Secrets Manager for storing credentials
  parameter_group_name   = "default.mysql8.0"
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.allow_mysql.id]
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  skip_final_snapshot    = true
}
