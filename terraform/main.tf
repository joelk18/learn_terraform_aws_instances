#####################
# S3 Buckets Setup #
#####################

# S3 Bucket for Data
resource "aws_s3_bucket" "data_bucket" {
}

# S3 Bucket for Glue Scripts
resource "aws_s3_bucket" "glue_scripts_bucket" {
}

#####################
# RDS MySQL Database #
#####################

resource "aws_db_instance" "rds_instance" {
  allocated_storage    = 5
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  db_name              = "etl_database"
  username             = var.rds_username
  password             = var.rds_password
  publicly_accessible  = true
  skip_final_snapshot  = true
}

####################
# Lambda Function #
####################

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-rds-populate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies for Lambda to access RDS
resource "aws_iam_policy_attachment" "lambda_rds_access" {
  name       = "lambda-rds-access"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

# Lambda Function
resource "aws_lambda_function" "populate_rds" {
  function_name    = "populate-rds-lambda"  # Add this required attribute
  filename         = "../artefacts/populate_db.zip"
  handler          = "populate_db.lambda_handler"
  runtime          = "python3.9"
  role             = aws_iam_role.lambda_role.arn
  timeout          = 30

  environment {
    variables = {
      RDS_HOST     = aws_db_instance.rds_instance.endpoint
      RDS_USER     = var.rds_username
      RDS_PASSWORD = var.rds_password
      RDS_DATABASE = aws_db_instance.rds_instance.db_name
    }
  }
}


# Trigger Lambda after RDS creation
resource "null_resource" "trigger_lambda" {
  depends_on = [aws_db_instance.rds_instance]

  provisioner "local-exec" {
    command = "aws lambda invoke --function-name ${aws_lambda_function.populate_rds.function_name} --region us-east-1 --profile joel_1 output.json"
  }
}

##############
# AWS Glue #
##############

# IAM Role for Glue
resource "aws_iam_role" "glue_role" {
  name = "glue-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "glue.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "glue_policy" {
  name = "GlueJobPolicy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "glue:GetConnection",
          "glue:GetConnections"
        ],
        Resource = "arn:aws:glue:eu-west-1:${data.aws_caller_identity.current.account_id}:connection/*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::your-target-bucket",
          "arn:aws:s3:::your-target-bucket/*"
        ]
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "glue_policy_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_policy.arn
}



#resource "aws_glue_crawler" "rds_crawler" {
#  name          = "rds-crawler"
#  role          = aws_iam_role.glue_role.arn
#  database_name = "glue_database"
#  jdbc_target {
#  connection_name = "rds_connection"
#  path            = "etl_database"
#}

#}


# Glue Job
resource "aws_glue_job" "glue_job" {
  name        = "etl-job"
  role_arn = aws_iam_role.glue_role.arn
  connections = [aws_glue_connection.rds_connection.name]
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_scripts_bucket.bucket}/glue_script.py"
    python_version  = "3"
  }
  max_capacity = 2
  default_arguments = {
    "--job-bookmark-option" = "job-bookmark-disable"
    "--TempDir"             = "s3://${aws_s3_bucket.glue_scripts_bucket.bucket}/temp"
    "--enable-metrics"      = "true"
    "--connection-name"     = aws_glue_connection.rds_connection.name
    "--db-name"             = "my_database"
    "--target_path"         = "s3://${aws_s3_bucket.glue_scripts_bucket.bucket}"
  }
}

# Define Glue Connection with dynamic JDBC URL
resource "aws_glue_connection" "rds_connection" {
  name = "rds_connection"

  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:mysql://${aws_db_instance.rds_instance.endpoint}:${aws_db_instance.rds_instance.port}/${aws_db_instance.rds_instance.db_name}"
    USERNAME            = var.rds_username
    PASSWORD            = var.rds_password
  }

  #physical_connection_requirements {
  #  availability_zone = aws_db_instance.rds_instance.availability_zone
  #  security_group_id_list = [
  #    aws_security_group.db_sg.id
  #  ]
  #  subnet_id = aws_subnet.db_subnet.id
  #}
}





# Upload Glue Script to S3
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.glue_scripts_bucket.bucket
  key    = "glue_script.py"
  source = "../scripts/glue_script.py"
}

#########################
# Automation & Triggers #
#########################

# EventBridge Rule for Scheduled Trigger
#resource "aws_eventbridge_rule" "trigger_glue_job" {
#  name                = "trigger-glue-job"
#  schedule_expression = "rate(1 day)" # Daily trigger
#}

# Permission for Glue to be triggered
#resource "aws_eventbridge_target" "glue_job_trigger" {
#  rule      = aws_eventbridge_rule.trigger_glue_job.name
#  arn       = aws_glue_job.glue_job.arn
#  role_arn  = aws_iam_role.glue_role.arn
#}
