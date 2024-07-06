provider "aws" {
    region = "us-east-1"
  
}



resource "tls_private_key" "key" {
    algorithm = "RSA"
    rsa_bits = 4096
  
}

resource "aws_key_pair" "keypair" {
    key_name_prefix = var.name_prefix
    public_key = tls_private_key.key.public_key_openssh
  
}

resource "aws_secretsmanager_secret" "secret_key" {
    name_prefix = var.name_prefix
    description = var.description
    tags = merge(
        var.tags,
        {"Name": "${var.name_prefix}-key"}
    )
  
}

resource "aws_secretsmanager_secret_version" "secret_key_value" {
    secret_id = aws_secretsmanager_secret.secret_key.id
    secret_string = tls_private_key.key.private_key_pem
  
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical's AWS Account ID
}


# Create a new EC2 instance
resource "aws_instance" "web" {
    ami           = data.aws_ami.ubuntu.id             # Amazon Machine Image ID for the instance
    instance_type = "t2.micro"      # Type of instance (e.g., t2.micro)
    key_name      = aws_key_pair.keypair.key_name  # Use the key pair created above

    tags = {
        Name = "${var.name_prefix}-ec2"
    }
    user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y python3 python3-pip
              ln -s /usr/bin/python3 /usr/bin/python
              EOF



}

# Output the private key to store it locally
output "private_key_pem" {
    value     = tls_private_key.key.private_key_pem
    sensitive = true
}

# Output the public IP of the EC2 instance
output "ec2_public_ip" {
    value = aws_instance.web.public_ip
}

data "aws_secretsmanager_secret_version" "secret_key" {
    secret_id = aws_secretsmanager_secret.secret_key.id
  
}

# Generate inventory file and retrieve private key using null_resource and local-exec
resource "null_resource" "setup" {
  provisioner "local-exec" {
    command = <<EOT
      echo "[web]" > hosts.ini
      echo "${aws_instance.web.public_ip}" >> hosts.ini

      echo "${data.aws_secretsmanager_secret_version.secret_key.secret_string}" > my-key.pem
      chmod 400 my-key.pem
    EOT
  }
}



