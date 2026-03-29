##############################################################################
# Create an RDS MySQL database
##############################################################################
resource "aws_db_instance" "project_db" {
  allocated_storage   = 10
  db_name             = var.dbname
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  username            = var.uname
  password            = var.pass
  skip_final_snapshot = true

  tags = {
    Name        = var.tag-name
    Environment = "Dev"
  }
}

##############################################################################
# Create 2 S3 buckets
##############################################################################
resource "aws_s3_bucket" "raw_bucket" {
  bucket = var.raw-bucket

  tags = {
    Name        = var.tag-name
    Environment = "Dev"
  }
}

resource "aws_s3_bucket" "finished_bucket" {
  bucket = var.finished-bucket

  tags = {
    Name        = var.tag-name
    Environment = "Dev"
  }
}

output "raw_url" {
  description = "Raw Bucket URL"
  value       = aws_s3_bucket.raw_bucket.bucket
}

##############################################################################
# Create an SNS Topic
##############################################################################
resource "aws_sns_topic" "user_updates" {
  name = var.sns-topic

  tags = {
    Name        = var.tag-name
    Environment = "project"
  }
}

##############################################################################
# Create an SQS Queue
##############################################################################
resource "aws_sqs_queue" "terraform_queue" {
  name = var.sqs

  tags = {
    Name        = var.tag-name
    Environment = "project"
  }
}

##############################################################################
# Create launch template
##############################################################################
resource "aws_launch_template" "lt" {
  image_id             = var.imageid
  instance_type        = var.instance-type
  key_name             = var.key-name
  vpc_security_group_ids = [var.vpc_security_group_ids]

  tags = {
    Name = var.tag-name
  }

  user_data = filebase64("./install-env.sh")
}

##############################################################################
# Get default VPC and subnets
##############################################################################
data "aws_vpc" "main" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

output "list-of-subnets" {
  description = "List of subnets"
  value       = data.aws_subnets.public.ids
}

data "aws_availability_zones" "available" {
  state = "available"
}

output "list-of-azs" {
  description = "List of AZs"
  value       = data.aws_availability_zones.available.names
}

##############################################################################
# Create Load Balancer
##############################################################################
resource "aws_lb" "lb" {
  name               = var.elb-name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.vpc_security_group_ids]
  subnets            = data.aws_subnets.public.ids

  enable_deletion_protection = false

  tags = {
    Name        = var.tag-name
    Environment = "project"
  }
}

output "url" {
  value = aws_lb.lb.dns_name
}

##############################################################################
# Create Auto Scaling Group
##############################################################################
resource "aws_autoscaling_group" "asg" {
  name                      = var.asg-name
  max_size                  = var.max
  min_size                  = var.min
  desired_capacity          = var.desired
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  target_group_arns         = [aws_lb_target_group.alb-lb-tg.arn]
  availability_zones        = data.aws_availability_zones.available.names

  launch_template {
    id = aws_launch_template.lt.id
  }
}

##############################################################################
# Create ALB Target Group
##############################################################################
resource "aws_lb_target_group" "alb-lb-tg" {
  depends_on  = [aws_lb.lb]
  name        = var.tg-name
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
}

##############################################################################
# Create ALB Listener
##############################################################################
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-lb-tg.arn
  }
}