# AWS US East 1
# Credentials from ~/.aws/credentials
provider "aws" {
  profile = "cbts"
  region = "us-east-1"
}

data "aws_availability_zones" "all" {}

# Whip up a VPC
resource "aws_vpc" "vpc" {
  cidr_block = "${var.vpc_cidr_block}"
  tags = {
    Name = "Velocloud"
  }
}
# Let's have that VPC ID
output "vpc_id" {
  value = "${aws_vpc.vpc.id}"
}


# Add Internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = {
    Name = "Internet gateway"
  }
}

resource "aws_default_route_table" "r" {
  default_route_table_id = "${aws_vpc.vpc.default_route_table_id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }
  tags = {
    Name = "Velocloud Public Table"
  }
}


# Create public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id     = "${aws_vpc.vpc.id}"
  availability_zone = "us-east-1d"
  cidr_block = "${var.public_cidr}"
  tags = {
    Name = "VCE Public Subnet"
  }
}


# Associate public subnet with its route table
resource "aws_route_table_association" "a" {
  subnet_id      = "${aws_subnet.public_subnet.id}"
  route_table_id = "${aws_default_route_table.r.id}"
}



# Create private route table
resource "aws_route_table" "p" {
  vpc_id = "${aws_vpc.vpc.id}"
#  route {
#    cidr_block = "0.0.0.0/0"
#    gateway_id = "${aws_network_interface.vce_lan.id}"
#  }
  tags = {
    Name = "Velocloud Private Routing Table"
  }
}


# And private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id     = "${aws_vpc.vpc.id}"
  availability_zone = "us-east-1d"
  cidr_block = "${var.private_cidr}"
  tags = {
    Name = "VCE Private Subnet"
  }
}


# Associate private_subnet subnet with its route table
resource "aws_route_table_association" "a2" {
  subnet_id      = "${aws_subnet.private_subnet.id}"
  route_table_id = "${aws_route_table.p.id}"
}


# Create security group
resource "aws_security_group" "allow_velocloud" {
  name        = "allow_velocloud"
  description = "Allow "
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress {
		from_port = "${var.velocloud_port}"
		to_port = "${var.velocloud_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
		from_port = "8"
		to_port = "0"
    protocol = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
		from_port = "22"
		to_port = "22"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle {
     create_before_destroy = true
   }
   tags = {
     Name = "allow_all"
   }
}


# Whip up the cloud-config file
# http://169.254.169.254/latest/user-data
data "template_file" "cloud-config" {
  template = "${file("scripts/init.cfg")}"
}
output "userdata" {
  value = "${data.template_file.cloud-config.rendered}"
}

data "template_cloudinit_config" "cloudinit" {
  gzip = false
  base64_encode = false
  part {
    filename = "init.cfg"
    content_type = "text/cloud-config"
    content = "${data.template_file.cloud-config.rendered}"
  }
}



# Deploy vedge
resource "aws_instance" "velocloud-edge" {
  ami             = "ami-da7a56cc"
  instance_type   = "m4.xlarge"
  key_name        = "Craig"
  security_groups = ["${aws_security_group.allow_velocloud.id}"]
  subnet_id       = "${aws_subnet.private_subnet.id}"
  source_dest_check = false
  user_data       = "data.template_cloudinit_config.cloudinit.rendered)}"
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name = "Velocloud Edge"
  }
#  provisioner "remote-exec" {
#    command = "reboot"
#  }
}


# Create an ENI for Velocloud LAN interface
resource "aws_network_interface" "vce_lan" {
  subnet_id       = "${aws_subnet.private_subnet.id}"
  security_groups = ["${aws_security_group.allow_velocloud.id}"]
  source_dest_check = false
  attachment {
    instance     = "${aws_instance.velocloud-edge.id}"
    device_index = 2
  }
  tags {
    Name = "VCE LAN Interface (GE3 / eth2)"
  }
}


# Create an ENI for eth1 Velocloud transport interface
resource "aws_network_interface" "transport" {
  subnet_id       = "${aws_subnet.public_subnet.id}"
  security_groups = ["${aws_security_group.allow_velocloud.id}"]
  source_dest_check = false
  attachment {
    instance     = "${aws_instance.velocloud-edge.id}"
    device_index = 1
  }
  tags {
    Name = "VCE Transport Interface (GE2 / eth1)"
  }
}


# Create EIP for Velocloud transport interface
resource "aws_eip" "transport" {
  vpc      = true
  network_interface = "${aws_network_interface.transport.id}"
}
# Let's have that public IP
output "transport-eip" {
  value = "${aws_eip.transport.public_ip}"
}


# Deploy jumpbox
resource "aws_instance" "jumpbox" {
  ami             = "ami-02da3a138888ced85"
  instance_type   = "t1.micro"
  key_name        = "Craig"
  security_groups = ["${aws_security_group.allow_velocloud.id}"]
  subnet_id       = "${aws_subnet.private_subnet.id}"
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name = "Velocloud Jumpbox"
  }
}


# Create an ENI for eth1 Jumpbox private interface
resource "aws_network_interface" "jumpbox_public" {
  subnet_id       = "${aws_subnet.public_subnet.id}"
  security_groups = ["${aws_security_group.allow_velocloud.id}"]
  source_dest_check = false
  attachment {
    instance     = "${aws_instance.jumpbox.id}"
    device_index = 1
  }
}


# Create EIP for reaching Jumpbox
resource "aws_eip" "jumpbox_eip" {
  vpc      = true
  network_interface = "${aws_network_interface.jumpbox_public.id}"
  provisioner "local-exec" {
    command = "scp -i ~/.ssh/craig.pem ~/.ssh/craig.pem ec2-user@${self.public_ip}:/home/ec2-user/.ssh"
  }
}
# Let's have that public IP
output "jumpbox_eip" {
  value = "${aws_eip.jumpbox_eip.public_ip}"
}
