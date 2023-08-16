terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-west-2"
}

resource "aws_vpc" "KenobiTFVPC" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "KenobiVPC"
  }
}

resource "aws_subnet" "TFSubnetPublic1" {
  vpc_id            = aws_vpc.KenobiTFVPC.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Terraform Public Subnet 1"
  }
}
resource "aws_subnet" "TFSubnetPublic2" {
  vpc_id            = aws_vpc.KenobiTFVPC.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Terraform Public Subnet 2"
  }
}
resource "aws_subnet" "TFSubnetPrivate1" {
  vpc_id            = aws_vpc.KenobiTFVPC.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "Terraform Private Subnet1"
  }
}
resource "aws_subnet" "TFSubnetPrivate2" {
  vpc_id            = aws_vpc.KenobiTFVPC.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "eu-west-2b"

  tags = {
    Name = "Terraform Private Subnet2"
  }
}
resource "aws_internet_gateway" "KenobiTFIGW" {
  vpc_id = aws_vpc.KenobiTFVPC.id

  tags = {
    Name = "Kenobi TF IGW"
  }
}
resource "aws_route_table" "PublicRouteTable" {
  vpc_id = aws_vpc.KenobiTFVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.KenobiTFIGW.id
  }


  tags = {
    Name = "Public Subnets Route Table"
  }
}
resource "aws_route_table_association" "Subnet1toroutetable1" {
  subnet_id      = aws_subnet.TFSubnetPublic1.id
  route_table_id = aws_route_table.PublicRouteTable.id
}
resource "aws_route_table_association" "Subnet2toroutetable1" {
  subnet_id      = aws_subnet.TFSubnetPublic2.id
  route_table_id = aws_route_table.PublicRouteTable.id
}


resource "aws_route_table" "PrivateRouteTable" {
  vpc_id = aws_vpc.KenobiTFVPC.id

  tags = {
    Name = "Private Subnets Route Table"
  }
}
resource "aws_route_table_association" "Subnet3toroutetable2" {
  subnet_id      = aws_subnet.TFSubnetPrivate1.id
  route_table_id = aws_route_table.PrivateRouteTable.id
}
resource "aws_route_table_association" "Subnet4toroutetable2" {
  subnet_id      = aws_subnet.TFSubnetPrivate2.id
  route_table_id = aws_route_table.PrivateRouteTable.id
}

resource "aws_security_group" "autoscaling_sg" {
  name        = "autoscaling security group"
  description = "Allow inbound from ALB and RDS"
  vpc_id      = aws_vpc.KenobiTFVPC.id

  ingress {
    description = "HTTP from ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
    egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "AutoScaling Security Group"
  }
}

resource "aws_vpc_security_group_ingress_rule" "autoscaling-security-group-ingress-from-RDS" {
  security_group_id = aws_security_group.autoscaling_sg.id
  description = "MySQL from RDS"
  from_port = 3306
  to_port = 3306
  ip_protocol = "tcp"
  referenced_security_group_id = aws_security_group.rds_sg.id
  depends_on = [aws_security_group.autoscaling_sg]

}

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Allow RDS traffic from autoscaling group"
  vpc_id      = aws_vpc.KenobiTFVPC.id

  ingress {
    description     = "RDS from autoscaling EC2s"
    from_port       = 3306
    to_port         = 3306
    protocol     = "tcp"
    security_groups = [aws_security_group.autoscaling_sg.id]
  }

  tags = {
    Name = "RDS Security Group"
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  description = "Security Group for Application Load Balancer"
  vpc_id      = aws_vpc.KenobiTFVPC.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  tags = {
    Name = "ALB Security Group"
  }
}


resource "aws_launch_template" "autoscaling_launch_template" {
  name_prefix            = "KenobiEC2-"
  image_id               = "ami-0d76271a8a1525c1a"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.autoscaling_sg.id]
  user_data = base64encode(<<-EOF
  #!/bin/bash
  yum update -y
  yum install -y httpd.x86_64
  systemctl start httpd.service
  systemctl enable httpd.service
  echo “Hello World from $(hostname -f)” > /var/www/html/index.html
  EOF
    )
}


resource "aws_autoscaling_group" "ec2_autoscaling" {
  name                      = "EC2 Autoscaling Group"
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 10
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.TFSubnetPublic1.id, aws_subnet.TFSubnetPublic2.id]
  target_group_arns = [aws_lb_target_group.alb_target_group.arn]
  launch_template {
    id = aws_launch_template.autoscaling_launch_template.id
  }
}

resource "aws_lb" "KenobiTFALB" {
  name            = "KenobiTF-alb"
  security_groups = [aws_security_group.alb_sg.id]
  subnets         = [aws_subnet.TFSubnetPublic1.id, aws_subnet.TFSubnetPublic2.id]



  tags = {
    Name = "Terraform ALB"
  }
}

resource "aws_lb_target_group" "alb_target_group" {
  name        = "Terraform-ALB-Target-Group"
  port        = 80
  protocol    = "HTTP"
  vpc_id = aws_vpc.KenobiTFVPC.id
  health_check {
    healthy_threshold = 3
    interval = 60
    unhealthy_threshold = 3
    matcher = "200"
  }
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.KenobiTFALB.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn
  }
}

resource "aws_cloudwatch_metric_alarm" "cw_alarm"{
  alarm_name = "Kenobi ALB TF Alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = 1
  period = 60
  statistic = "Sum"
  namespace = "AWS/ApplicationELB"
  metric_name = "RequestCount"
  threshold = 100
  dimensions = {
    LoadBalancer = aws_lb.KenobiTFALB.arn
  }

}


resource "aws_db_subnet_group" "SubnetGroup" {
  name       = "rds_subnet_group"
  subnet_ids = [aws_subnet.TFSubnetPublic1.id, aws_subnet.TFSubnetPublic2.id]

  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_db_instance" "TerraformKenobiRDS" {
  allocated_storage    = 5
  db_name              = "TerraformDB"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  username             = "kenobi"
  manage_master_user_password = true
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.SubnetGroup.id
}
