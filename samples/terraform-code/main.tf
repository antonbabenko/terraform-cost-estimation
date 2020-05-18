// Terraform code featuring resources covered by https://github.com/antonbabenko/terraform-cost-estimation
//
// aws_instance
// aws_ec2_fleet
// aws_ebs_volume
// aws_ebs_snapshot
// aws_ebs_snapshot_copy

// aws_autoscaling_group
// aws_launch_template
// aws_launch_tconfiguration

// aws_lb / aws_alb
// aws_elb
// aws_nat_gateway

#################
# EC2 instance
#################
resource "aws_instance" "this_1" {
  ami           = data.aws_ami.amazon_linux2.id #"ami-06ce3edf0cff21f07"
  instance_type = "t3.nano"

  ebs_block_device { # "standard", "gp2", "io1", "sc1", or "st1". (Default: "gp2").
    device_name = "xvfs"
    volume_size = 10
  }

  ebs_block_device {
    device_name = "xvfa"
    volume_size = 20
    volume_type = "sc1"
  }

  ebs_block_device {
    device_name = "xvfb"
    volume_size = 30
    volume_type = "io1"
    iops        = 2000
  }

  root_block_device {
    volume_type = "io1" # "standard", "gp2", "io1", "sc1", or "st1". (Default: "standard").
    iops        = 220
  }
}

#################
# EBS Volume - standard
#################
resource "aws_ebs_volume" "volume_standard" {
  availability_zone = data.aws_availability_zones.available.names[0] #"eu-west-1a"
  size              = 7
  type              = "standard" # "gp2", "io1", "sc1" or "st1" (Default: "gp2").
}

#################
# EBS Volume - io1
#################
resource "aws_ebs_volume" "volume_io1" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = 8
  iops              = 300
  type              = "io1"
}

#################
# EBS Snapshot
#################
resource "aws_ebs_snapshot" "standard" {
  volume_id = aws_ebs_volume.volume_standard.id
}

#################
# EBS Snapshot copy
#################
resource "aws_ebs_snapshot_copy" "copied" {
  source_region      = data.aws_region.selected.name
  source_snapshot_id = aws_ebs_snapshot.standard.id
}

##############################################
# Autoscaling group with Launch Configuration
##############################################
resource "aws_autoscaling_group" "lc" {
  desired_capacity    = 1
  max_size            = 2
  min_size            = 0
  vpc_zone_identifier = tolist(data.aws_subnet_ids.all.ids)

  launch_configuration = aws_launch_configuration.lc.id
}

resource "aws_launch_configuration" "lc" {
  image_id      = data.aws_ami.amazon_linux2.id
  instance_type = "t2.micro"
}

#########################################
# Autoscaling group with Launch Template
#########################################
resource "aws_autoscaling_group" "lt" {
  desired_capacity    = 1
  max_size            = 2
  min_size            = 0
  vpc_zone_identifier = tolist(data.aws_subnet_ids.all.ids)

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
}

#########################################
# EC2 fleet with Launch Template
#########################################
resource "aws_ec2_fleet" "lt" {
  launch_template_config {
    launch_template_specification {
      launch_template_id = aws_launch_template.lt.id
      version            = aws_launch_template.lt.latest_version
    }
//    // For internal tests
//    launch_template_specification {
//      launch_template_id = element(aws_launch_template.lt.*.id, 0)
//      version            = aws_launch_template.lt[0].latest_version
//    }
  }

  target_capacity_specification {
    default_target_capacity_type = "on-demand"
    total_target_capacity        = 1
  }
}

resource "aws_launch_template" "lt" {
  image_id      = data.aws_ami.amazon_linux2.id
  instance_type = "t2.nano"

  elastic_gpu_specifications {
    type = "eg1.medium"
  }

  elastic_gpu_specifications {
    type = "eg1.large"
  }

  elastic_inference_accelerator { // this is not part of EC2 pricing
    type = "eia1.medium"
  }
}

#########################################
# Application and Network Load Balancers
#########################################
resource "aws_alb" "alb" {
  load_balancer_type = "application"
  subnets            = data.aws_subnet_ids.all.ids
}

resource "aws_lb" "nlb" {
  load_balancer_type = "network"
  subnets            = data.aws_subnet_ids.all.ids
}

##########################
# ELB
##########################
resource "aws_elb" "elb" {
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  subnets = data.aws_subnet_ids.all.ids
}

##########################
# NAT Gateway
##########################
resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = tolist(data.aws_subnet_ids.all.ids)[0]
}
